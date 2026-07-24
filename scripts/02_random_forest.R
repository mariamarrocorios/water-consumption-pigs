# =========================================================
# 02 - RANDOM FOREST - WATER CONSUMPTION
# Leave-one-batch-out validation within each production unit.
# =========================================================

source("scripts/utils.R")
library(readxl)
library(dplyr)
library(randomForest)
library(ggplot2)

data_file <- "data/Water_Database_simulated.xlsx"   # replace with your own file
output_dir <- "outputs"
if(!dir.exists(output_dir)) dir.create(output_dir)

D <- load_water_data(data_file)
buildings <- unique(D$Building_name)

# -----------------------------
# RUN ONE BATCH
# -----------------------------

run_batch_RF <- function(batch, D, building){

  message("[Random Forest] building: ", building, " | batch: ", batch)

  test.set  <- D[D$lotcode == batch, ]
  train.set <- D[D$lotcode != batch, ]

  if(nrow(test.set) == 0 || nrow(train.set) == 0) return(NULL)

  train.set <- train.set %>% na.omit()
  test.set  <- test.set  %>% na.omit()

  if(nrow(test.set) == 0 || nrow(train.set) == 0) return(NULL)

  set.seed(123)
  rf_model <- randomForest(
    x = train.set[, full_predictor_set],
    y = train.set$water_L,
    ntree = 300,
    importance = TRUE
  )

  pred <- predict(rf_model, newdata = test.set[, full_predictor_set])
  errors <- pred - test.set$water_L

  hourly.out <- data.frame(
    Building_name = building, Test.set = batch,
    Date = test.set$Date, Hour = test.set$Hour,
    N_Days = test.set$N_Days, Total_hour = test.set$Total_hour,
    Real = test.set$water_L, Pred = as.numeric(pred), Error = as.numeric(errors)
  )

  summary.out <- data.frame(
    Building_name = building, Test.set = batch,
    RMSE = RMSE(errors), MAE = MAE(errors),
    N_Days_adapted = calculate_N_Days_adapted(errors, test.set$N_Days)
  )

  list(summary = summary.out, hourly = hourly.out, model = rf_model)
}

# -----------------------------
# MAIN LOOP
# -----------------------------

all.results <- list()
all.hourly.results <- list()

for(b in buildings){

  message("====================================")
  message("Processing building: ", b)
  message("====================================")

  D_building <- D[D$Building_name == b, ]
  D_building <- create_lags(D_building)
  D_building <- feature_engineering(D_building)
  D_building <- D_building %>% filter(if_all(starts_with("lag_"), ~ !is.na(.)))

  batches <- unique(D_building$lotcode)

  results <- lapply(batches, run_batch_RF, D = D_building, building = b)
  results <- results[!sapply(results, is.null)]

  if(length(results) > 0){
    all.results[[b]] <- do.call(rbind, lapply(results, function(x) x$summary))
    all.hourly.results[[b]] <- do.call(rbind, lapply(results, function(x) x$hourly))
  }
}

final.results_RF  <- do.call(rbind, all.results)
hourly.results_RF <- do.call(rbind, all.hourly.results)

print(final.results_RF)

saveRDS(final.results_RF,  file.path(output_dir, "results_RF.rds"))
saveRDS(hourly.results_RF, file.path(output_dir, "hourly_results_RF.rds"))

message("Random Forest completed. Results saved in: ", output_dir)
