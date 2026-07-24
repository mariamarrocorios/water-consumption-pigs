# =========================================================
# 03 - XGBOOST - WATER CONSUMPTION
# Leave-one-batch-out validation within each production unit.
#
# NOTE: xgboost is not part of base R / CRAN mirrors reachable
# from every environment. Install it with:
#   install.packages("xgboost")
# =========================================================

source("scripts/utils.R")
library(readxl)
library(dplyr)
library(ggplot2)
library(xgboost)

data_file <- "data/Water_Database_simulated.xlsx"   # replace with your own file
output_dir <- "outputs"
if(!dir.exists(output_dir)) dir.create(output_dir)

D <- load_water_data(data_file)
buildings <- unique(D$Building_name)

# -----------------------------
# RUN ONE BATCH
# -----------------------------

run_batch_XGB <- function(batch, D, building){

  message("[XGBoost] building: ", building, " | batch: ", batch)

  test.set  <- D[D$lotcode == batch, ]
  train.set <- D[D$lotcode != batch, ]

  if(nrow(test.set) == 0 || nrow(train.set) == 0) return(NULL)

  train.set <- train.set %>% na.omit()
  test.set  <- test.set  %>% na.omit()

  if(nrow(test.set) == 0 || nrow(train.set) == 0) return(NULL)

  train.x <- train.set[, full_predictor_set, drop = FALSE]
  test.x  <- test.set[,  full_predictor_set, drop = FALSE]

  # remove zero-variance predictors (can occur with small example datasets)
  feature_sds <- sapply(train.x, sd, na.rm = TRUE)
  valid_features <- names(feature_sds[!is.na(feature_sds) & feature_sds > 0])

  if(length(valid_features) < 2) return(NULL)

  train.x <- train.x[, valid_features, drop = FALSE]
  test.x  <- test.x[,  valid_features, drop = FALSE]

  train.ok <- complete.cases(train.x) & is.finite(train.set$water_L)
  test.ok  <- complete.cases(test.x)

  train.x <- train.x[train.ok, , drop = FALSE]
  test.x  <- test.x[test.ok, , drop = FALSE]

  train.y <- train.set$water_L[train.ok]
  test.meta <- test.set[test.ok, , drop = FALSE]

  if(nrow(train.x) < 20 || nrow(test.x) == 0) return(NULL)

  dtrain <- xgb.DMatrix(data = as.matrix(train.x), label = train.y)
  dtest  <- xgb.DMatrix(data = as.matrix(test.x))

  params <- list(
    objective = "reg:squarederror",
    eval_metric = "rmse",
    eta = 0.05,
    max_depth = 6,
    min_child_weight = 3,
    subsample = 0.8,
    colsample_bytree = 0.8
  )

  set.seed(123)
  xgb_model <- xgb.train(params = params, data = dtrain, nrounds = 300, verbose = 0)

  pred <- predict(xgb_model, newdata = dtest)
  errors <- pred - test.meta$water_L

  hourly.out <- data.frame(
    Building_name = building, Test.set = batch,
    Date = test.meta$Date, Hour = test.meta$Hour,
    N_Days = test.meta$N_Days, Total_hour = test.meta$Total_hour,
    Real = as.numeric(test.meta$water_L), Pred = as.numeric(pred), Error = as.numeric(errors)
  )

  summary.out <- data.frame(
    Building_name = building, Test.set = batch,
    RMSE = RMSE(errors), MAE = MAE(errors),
    N_Days_adapted = calculate_N_Days_adapted(errors, test.meta$N_Days)
  )

  list(summary = summary.out, hourly = hourly.out)
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

  results <- lapply(batches, run_batch_XGB, D = D_building, building = b)
  results <- results[!sapply(results, is.null)]

  if(length(results) > 0){
    all.results[[b]] <- do.call(rbind, lapply(results, function(x) x$summary))
    all.hourly.results[[b]] <- do.call(rbind, lapply(results, function(x) x$hourly))
  }
}

final.results_XGB  <- do.call(rbind, all.results)
hourly.results_XGB <- do.call(rbind, all.hourly.results)

print(final.results_XGB)

saveRDS(final.results_XGB,  file.path(output_dir, "results_XGB.rds"))
saveRDS(hourly.results_XGB, file.path(output_dir, "hourly_results_XGB.rds"))

message("XGBoost completed. Results saved in: ", output_dir)
