# =========================================================
# 01 - LINEAR REGRESSION - WATER CONSUMPTION
# Fits two formulations per test batch, using a leave-one-
# batch-out strategy within each production unit:
#   - baseline: contextual variables only (Hour, N_Days, num_animals)
#   - extended: contextual variables + 24 lags + rolling 24h stats
# =========================================================

source("scripts/utils.R")
library(readxl)
library(dplyr)
library(ggplot2)

data_file <- "data/Water_Database_simulated.xlsx"   # replace with your own file
output_dir <- "outputs"
if(!dir.exists(output_dir)) dir.create(output_dir)

D <- load_water_data(data_file)
buildings <- unique(D$Building_name)

# -----------------------------
# RUN ONE BATCH (either formulation)
# -----------------------------

run_batch_LM <- function(batch, D, building, features, model_label){

  message("[", model_label, "] building: ", building, " | batch: ", batch)

  test.set  <- D[D$lotcode == batch, ]
  train.set <- D[D$lotcode != batch, ]

  if(nrow(test.set) == 0 || nrow(train.set) == 0) return(NULL)

  train.set <- train.set %>% na.omit()
  test.set  <- test.set  %>% na.omit()

  if(nrow(test.set) == 0 || nrow(train.set) == 0) return(NULL)

  formula_lm <- as.formula(paste("water_L ~", paste(features, collapse = " + ")))
  lm_model <- lm(formula_lm, data = train.set)

  pred <- predict(lm_model, newdata = test.set)

  valid_idx <- which(!is.na(pred))
  test.set <- test.set[valid_idx, , drop = FALSE]
  pred <- pred[valid_idx]

  if(length(pred) == 0) return(NULL)

  errors <- pred - test.set$water_L

  hourly.out <- data.frame(
    Building_name = building, Test.set = batch,
    Date = test.set$Date, Hour = test.set$Hour,
    N_Days = test.set$N_Days, Total_hour = test.set$Total_hour,
    Real = test.set$water_L, Pred = as.numeric(pred), Error = as.numeric(errors),
    Model = model_label
  )

  summary.out <- data.frame(
    Building_name = building, Test.set = batch,
    RMSE = RMSE(errors), MAE = MAE(errors),
    N_Days_adapted = calculate_N_Days_adapted(errors, test.set$N_Days),
    Model = model_label
  )

  list(summary = summary.out, hourly = hourly.out)
}

# -----------------------------
# MAIN LOOP (per unit, per formulation)
# -----------------------------

features_baseline <- c("Hour", "N_Days", "num_animals")
features_extended <- full_predictor_set

run_all <- function(features, model_label, needs_lags){

  all.results <- list()
  all.hourly  <- list()

  for(b in buildings){

    D_building <- D[D$Building_name == b, ]

    if(needs_lags){
      D_building <- create_lags(D_building)
      D_building <- feature_engineering(D_building)
      D_building <- D_building %>% filter(if_all(starts_with("lag_"), ~ !is.na(.)))
    }

    batches <- unique(D_building$lotcode)

    results <- lapply(batches, run_batch_LM, D = D_building, building = b,
                       features = features, model_label = model_label)
    results <- results[!sapply(results, is.null)]

    if(length(results) > 0){
      all.results[[b]] <- do.call(rbind, lapply(results, function(x) x$summary))
      all.hourly[[b]]  <- do.call(rbind, lapply(results, function(x) x$hourly))
    }
  }

  list(
    summary = do.call(rbind, all.results),
    hourly  = do.call(rbind, all.hourly)
  )
}

out_baseline <- run_all(features_baseline, "LR_baseline", needs_lags = FALSE)
out_extended <- run_all(features_extended, "LR_extended", needs_lags = TRUE)

final.results_LR  <- rbind(out_baseline$summary, out_extended$summary)
hourly.results_LR <- rbind(out_baseline$hourly,  out_extended$hourly)

print(final.results_LR)

saveRDS(final.results_LR,  file.path(output_dir, "results_LR.rds"))
saveRDS(hourly.results_LR, file.path(output_dir, "hourly_results_LR.rds"))

message("Linear Regression completed. Results saved in: ", output_dir)
