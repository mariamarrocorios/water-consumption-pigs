# =========================================================
# SHARED UTILITY FUNCTIONS
# Used by all modelling scripts (01-04) in this repository.
# Sourced at the top of each script with: source("scripts/utils.R")
# =========================================================

library(dplyr)

# ---------------------------------------------------------
# ERROR METRICS
# ---------------------------------------------------------

RMSE <- function(x) sqrt(mean(x^2, na.rm = TRUE))
MAE  <- function(x) mean(abs(x), na.rm = TRUE)

# ---------------------------------------------------------
# CREATE LAGGED WATER CONSUMPTION VARIABLES (lag_1 - lag_24)
# ---------------------------------------------------------

create_lags <- function(df, max_lag = 24){

  df <- df %>%
    arrange(lotcode, Total_hour) %>%
    group_by(lotcode)

  for(i in 1:max_lag){
    df[[paste0("lag_", i)]] <- dplyr::lag(df$water_L, i)
  }

  df <- df %>% ungroup()

  return(df)
}

# ---------------------------------------------------------
# ROLLING 24-HOUR SUMMARY STATISTICS (mean, max, min)
# ---------------------------------------------------------

feature_engineering <- function(df){

  lag_cols <- paste0("lag_", 1:24)

  df <- df %>%
    mutate(
      mean_24 = ifelse(
        rowSums(!is.na(select(., all_of(lag_cols)))) > 0,
        rowMeans(select(., all_of(lag_cols)), na.rm = TRUE),
        NA
      ),
      max_24 = apply(select(., all_of(lag_cols)), 1, function(x){
        if(all(is.na(x))) NA else max(x, na.rm = TRUE)
      }),
      min_24 = apply(select(., all_of(lag_cols)), 1, function(x){
        if(all(is.na(x))) NA else min(x, na.rm = TRUE)
      })
    )

  return(df)
}

# ---------------------------------------------------------
# ADAPTATION TIME METRIC
# First fattening day at which daily RMSE drops and stays
# below (mean + 2 SD) of the daily RMSE series for that batch
# ---------------------------------------------------------

calculate_N_Days_adapted <- function(errors, N_Days){

  agg <- aggregate(x = errors, by = list(N_Days), FUN = RMSE)
  colnames(agg) <- c("N_Days", "RMSE")

  Mean <- mean(agg$RMSE, na.rm = TRUE)
  SD   <- sd(agg$RMSE, na.rm = TRUE)

  idx_adapt <- which(agg$RMSE < (Mean + 2 * SD))[1]

  N_Days_adapted <- ifelse(length(idx_adapt) == 0 || is.na(idx_adapt),
                           NA,
                           agg$N_Days[idx_adapt])

  return(N_Days_adapted)
}

# ---------------------------------------------------------
# STANDARD PREDICTOR SET
# Contextual variables + 24 lags + rolling 24h statistics
# (used by LR-extended, Random Forest, XGBoost, Neural Network)
# ---------------------------------------------------------

full_predictor_set <- c(
  paste0("lag_", 1:24),
  "Hour",
  "N_Days",
  "num_animals",
  "mean_24",
  "max_24",
  "min_24"
)

# ---------------------------------------------------------
# LOAD AND PREPARE THE RAW DATASET
# path: path to the Excel file (real or simulated)
# max_water: implausible-value cutoff (L/hour), matching the
#            original study (observations >= 1000 L/h excluded)
# ---------------------------------------------------------

load_water_data <- function(path, max_water = 1000){

  D <- as.data.frame(readxl::read_xlsx(path))

  D <- D[, c("Building_name", "lotcode", "Date", "Hour",
             "num_animals", "water_L", "N_Days", "Total_hour")]

  D <- subset(D, D$water_L < max_water)

  return(D)
}
