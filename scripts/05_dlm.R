# =========================================================
# 05 - DYNAMIC LINEAR MODEL (DLM) - WATER CONSUMPTION
#
# NOT RUNNABLE OUT OF THE BOX.
#
# Unlike the other four scripts in this repository, the DLM
# relies on a set of custom state-space modelling functions
# (implementing the framework described by Madsen & Kristensen,
# 2005) that were developed for teaching purposes and are not
# included in this repository. To run this script you will
# need the following three files, sourced below, which define
# (among others) get.mu0_and_C0(), get.Gt(), get.Ft(),
# runEM_earlyStopping(), and runDLM():
#
#   - "DLM_functions.R"
#   - "Custom_get_Gt_and_get_Ft_functions.R"
#   - "FUNCTIONS.R"
#
# If you have access to these functions (e.g. through the
# original teaching material referenced in the accompanying
# publication), place them in a local "dlm_dependencies/"
# folder and this script will source them automatically.
# Otherwise, the DLM step can simply be skipped: scripts 01-04
# and 06 run independently of this file, and 06 automatically
# excludes the DLM from the comparison if results_DLM.rds is
# not found.
# =========================================================

source("scripts/utils.R")

dep_dir <- "dlm_dependencies"
required_files <- c(
  "DLM_functions.R",
  "Custom_get_Gt_and_get_Ft_functions.R",
  "FUNCTIONS.R"
)
dep_paths <- file.path(dep_dir, required_files)

if(!all(file.exists(dep_paths))){
  message(
    "DLM dependencies not found in '", dep_dir, "/'. ",
    "Skipping DLM. See the header of this script for details ",
    "on what is required to run it."
  )
} else {

  for(f in dep_paths) source(f)

  library(readxl)
  library(ggplot2)

  data_file  <- "data/Water_Database_simulated.xlsx"   # replace with your own file
  output_dir <- "outputs"
  if(!dir.exists(output_dir)) dir.create(output_dir)

  D <- load_water_data(data_file)
  buildings <- unique(D$Building_name)

  relevant.names <- c("water_L")
  N.w.all <- c(3)
  trend.all <- c(TRUE)
  w.all <- c((2 * pi) / 24)
  time.var.names.All <- c("Hour")

  standardize_sets <- function(learning.set, test.set, variables){

    scaling_params <- list()

    for(name in variables){
      Mean <- mean(learning.set[[name]], na.rm = TRUE)
      SD   <- sd(learning.set[[name]], na.rm = TRUE)
      if(is.na(SD) || SD == 0) SD <- 1

      learning.set[[name]] <- (learning.set[[name]] - Mean) / SD
      test.set[[name]]     <- (test.set[[name]] - Mean) / SD

      scaling_params[[name]] <- list(mean = Mean, sd = SD)
    }

    list(learning = learning.set, test = test.set, scaling_params = scaling_params)
  }

  run_batch_DLM <- function(batch, D, building){

    message("[DLM] building: ", building, " | batch: ", batch)

    test.set.original <- D[D$lotcode == batch, ]
    learning.set.original <- D[D$lotcode != batch, ]

    if(nrow(test.set.original) == 0 || nrow(learning.set.original) == 0) return(NULL)

    std <- standardize_sets(learning.set.original, test.set.original, relevant.names)
    learning.set <- std$learning
    test.set <- std$test

    mean_y <- std$scaling_params[["water_L"]]$mean
    sd_y   <- std$scaling_params[["water_L"]]$sd

    a <- get.mu0_and_C0(Data = learning.set, relevant.names, time.var.names.All,
                        trend.all, N.w.all, w.all)
    mu0 <- a$mu0
    C0  <- a$C0

    set.seed(111)
    EM.out <- runEM_earlyStopping(
      Data = learning.set, stratify.by = NA, Spline.list = NA,
      identifyer = "lotcode", V0 = NA, W0 = NA,
      C0.list = list(C0), mu0.list = list(mu0),
      no.better.limit = 2, time.var = "Hour",
      relevant.names, round.by = 4
    )

    res <- runDLM(
      Data = test.set,
      mu0 = EM.out$mu0.list[[1]], C0 = EM.out$C0.list[[1]],
      V = EM.out$V.list[[1]], W = EM.out$W.list[[1]],
      adjust.W = FALSE, delta = NA, relevant.names,
      Spline.list = NA, time.var = "Hour"
    )

    pred_std <- as.numeric(unlist(res$ft))
    real_std <- as.numeric(test.set[["water_L"]])

    n <- min(length(pred_std), length(real_std), nrow(test.set.original))
    if(n == 0) return(NULL)

    pred <- pred_std[1:n] * sd_y + mean_y
    real <- real_std[1:n] * sd_y + mean_y
    test.set.original <- test.set.original[1:n, , drop = FALSE]

    errors <- pred - real

    hourly.out <- data.frame(
      Building_name = building, Test.set = batch,
      Date = test.set.original$Date, Hour = test.set.original$Hour,
      N_Days = test.set.original$N_Days, Total_hour = test.set.original$Total_hour,
      Real = real, Pred = pred, Error = errors
    )

    summary.out <- data.frame(
      Building_name = building, Test.set = batch,
      RMSE = RMSE(errors), MAE = MAE(errors),
      N_Days_adapted = calculate_N_Days_adapted(errors, test.set.original$N_Days)
    )

    list(summary = summary.out, hourly = hourly.out)
  }

  all.results <- list()
  all.hourly.results <- list()

  for(b in buildings){

    D_building <- D[D$Building_name == b, ]
    batches <- unique(D_building$lotcode)

    results <- lapply(batches, run_batch_DLM, D = D_building, building = b)
    results <- results[!sapply(results, is.null)]

    if(length(results) > 0){
      all.results[[b]] <- do.call(rbind, lapply(results, function(x) x$summary))
      all.hourly.results[[b]] <- do.call(rbind, lapply(results, function(x) x$hourly))
    }
  }

  final.results_DLM  <- do.call(rbind, all.results)
  hourly.results_DLM <- do.call(rbind, all.hourly.results)

  print(final.results_DLM)

  saveRDS(final.results_DLM,  file.path(output_dir, "results_DLM.rds"))
  saveRDS(hourly.results_DLM, file.path(output_dir, "hourly_results_DLM.rds"))

  message("DLM completed. Results saved in: ", output_dir)
}
