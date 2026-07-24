# =========================================================
# 04 - NEURAL NETWORK (MLP) - WATER CONSUMPTION
# Single hidden-layer MLP, leave-one-batch-out validation
# within each production unit. Predictors and response are
# standardised prior to training.
# =========================================================

source("scripts/utils.R")
library(readxl)
library(dplyr)
library(ggplot2)
library(nnet)

data_file <- "data/Water_Database_simulated.xlsx"   # replace with your own file
output_dir <- "outputs"
if(!dir.exists(output_dir)) dir.create(output_dir)

D <- load_water_data(data_file)
buildings <- unique(D$Building_name)

# -----------------------------
# STANDARDISATION HELPER
# -----------------------------

standardize_train_test <- function(train.set, test.set, features, target){

  means_x <- sapply(train.set[, features, drop = FALSE], mean, na.rm = TRUE)
  sds_x   <- sapply(train.set[, features, drop = FALSE], sd,   na.rm = TRUE)
  sds_x[is.na(sds_x) | sds_x == 0] <- 1

  train.x <- as.data.frame(scale(train.set[, features, drop = FALSE], center = means_x, scale = sds_x))
  test.x  <- as.data.frame(scale(test.set[,  features, drop = FALSE], center = means_x, scale = sds_x))

  mean_y <- mean(train.set[[target]], na.rm = TRUE)
  sd_y   <- sd(train.set[[target]], na.rm = TRUE)
  if(is.na(sd_y) || sd_y == 0) sd_y <- 1

  train.y <- (train.set[[target]] - mean_y) / sd_y

  list(train.x = train.x, test.x = test.x, train.y = train.y, mean_y = mean_y, sd_y = sd_y)
}

# -----------------------------
# RUN ONE BATCH
# -----------------------------

run_batch_NN <- function(batch, D, building){

  message("[Neural Network] building: ", building, " | batch: ", batch)

  test.set  <- D[D$lotcode == batch, ]
  train.set <- D[D$lotcode != batch, ]

  if(nrow(test.set) == 0 || nrow(train.set) == 0) return(NULL)

  train.set <- train.set %>% na.omit()
  test.set  <- test.set  %>% na.omit()

  if(nrow(test.set) == 0 || nrow(train.set) == 0) return(NULL)

  feature_sds <- sapply(train.set[, full_predictor_set, drop = FALSE], sd, na.rm = TRUE)
  features <- names(feature_sds[!is.na(feature_sds) & feature_sds > 0])

  if(length(features) < 2) return(NULL)

  std <- standardize_train_test(train.set, test.set, features, target = "water_L")

  train.x <- std$train.x
  test.x  <- std$test.x
  train.y <- std$train.y

  train.ok <- complete.cases(train.x) & is.finite(train.y)
  test.ok  <- complete.cases(test.x)

  train.x <- train.x[train.ok, , drop = FALSE]
  train.y <- train.y[train.ok]
  test.x  <- test.x[test.ok, , drop = FALSE]
  test.set <- test.set[test.ok, , drop = FALSE]

  if(nrow(train.x) < 20 || nrow(test.x) == 0) return(NULL)

  size_nn <- min(8, max(3, floor(ncol(train.x) / 4)))

  set.seed(123)
  nn_model <- nnet(
    x = as.matrix(train.x), y = train.y,
    size = size_nn, linout = TRUE, decay = 0.001,
    maxit = 500, trace = FALSE, MaxNWts = 10000
  )

  pred_scaled <- predict(nn_model, newdata = as.matrix(test.x))
  pred <- as.numeric(pred_scaled) * std$sd_y + std$mean_y

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

  results <- lapply(batches, run_batch_NN, D = D_building, building = b)
  results <- results[!sapply(results, is.null)]

  if(length(results) > 0){
    all.results[[b]] <- do.call(rbind, lapply(results, function(x) x$summary))
    all.hourly.results[[b]] <- do.call(rbind, lapply(results, function(x) x$hourly))
  }
}

final.results_NN  <- do.call(rbind, all.results)
hourly.results_NN <- do.call(rbind, all.hourly.results)

print(final.results_NN)

saveRDS(final.results_NN,  file.path(output_dir, "results_NN.rds"))
saveRDS(hourly.results_NN, file.path(output_dir, "hourly_results_NN.rds"))

message("Neural Network completed. Results saved in: ", output_dir)
