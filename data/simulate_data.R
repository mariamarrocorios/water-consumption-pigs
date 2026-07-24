# =========================================================
# SIMULATE EXAMPLE DATASET
# Generates a synthetic dataset with the same structure as
# the original Water_Database.xlsx used in the study, so
# that the modelling scripts in this repository can be run
# end-to-end without access to the original commercial data.
#
# IMPORTANT: This is SIMULATED data for demonstration
# purposes only. It reproduces the general shape of hourly
# water consumption (circadian pattern + growth trend +
# occasional spikes) but does not represent real animals,
# farms, or measurements.
# =========================================================

set.seed(2026)

# ---------------------------------------------------------
# SETTINGS
# ---------------------------------------------------------

building_name   <- "Farm_1.0.1"   # single simulated unit
n_batches       <- 3              # number of consecutive batches
n_days          <- 45             # fattening days per batch (shortened for a fast demo;
                                   # real batches in the study ranged 112-155 days)
start_animals   <- 700            # animals at the start of each batch

output_file <- file.path("data", "Water_Database_simulated.xlsx")

# ---------------------------------------------------------
# SIMULATE ONE BATCH
# ---------------------------------------------------------

simulate_batch <- function(lotcode, start_date){

  n_hours <- n_days * 24
  hour_of_day <- rep(0:23, times = n_days)
  n_day_vec   <- rep(1:n_days, each = 24)
  total_hour  <- seq_len(n_hours)

  dates <- as.POSIXct(start_date, tz = "UTC") + (n_day_vec - 1) * 86400

  # --- growth trend: consumption increases with fattening day,
  # plateaus, then declines slightly near the end (partial depopulation) ---
  growth_trend <- 90 + 75 * (1 - exp(-n_day_vec / 25))
  end_decline  <- ifelse(n_day_vec > n_days * 0.85,
                          1 - 0.25 * (n_day_vec - n_days * 0.85) / (n_days * 0.15),
                          1)
  daily_level <- growth_trend * end_decline

  # --- circadian pattern: low at night, peaks in the morning and afternoon ---
  circadian <- 0.35 +
    0.55 * exp(-((hour_of_day - 11) %% 24 - 0)^2 / 18) +
    0.65 * exp(-((hour_of_day - 17) %% 24 - 0)^2 / 10) +
    0.15 * exp(-((hour_of_day - 21) %% 24 - 0)^2 / 8)

  base_signal <- daily_level * circadian

  # --- noise ---
  noise <- rnorm(n_hours, mean = 0, sd = 0.12 * pmax(base_signal, 5))

  water_L <- pmax(base_signal + noise, 0)

  # --- occasional large, isolated spikes (~0.5% of hours) ---
  n_spikes <- round(0.005 * n_hours)
  spike_idx <- sample(which(hour_of_day %in% 8:19), n_spikes)
  water_L[spike_idx] <- water_L[spike_idx] + runif(n_spikes, 150, 400)

  # --- number of animals: stable, gradual partial depopulation near the end ---
  num_animals <- round(start_animals * end_decline)

  # --- other monitored variables (simulated, not used by the modelling
  # scripts, but included to mirror the original file structure) ---
  feed_intake_kg      <- round(pmax(base_signal * 0.6 + rnorm(n_hours, 0, 1), 0), 1)
  nh3                 <- round(runif(n_hours, 5, 20), 1)
  co2                 <- round(runif(n_hours, 800, 2200), 0)
  humidity            <- round(runif(n_hours, 55, 75), 1)
  outside_temperature <- round(10 + 8 * sin(2 * pi * total_hour / (24 * 365)) +
                                  rnorm(n_hours, 0, 2), 1)
  inside_temperature  <- round(22 + rnorm(n_hours, 0, 1.2), 1)
  indiv_water_ml      <- round((water_L * 1000) / pmax(num_animals, 1), 2)

  data.frame(
    Building_name        = building_name,
    lotcode               = lotcode,
    Date                   = dates,
    Hour                   = hour_of_day,
    Feed_intake_kg         = feed_intake_kg,
    num_animals            = num_animals,
    water_L                = round(water_L, 1),
    NH3                    = nh3,
    CO2                    = co2,
    Humidity               = humidity,
    Outside_temperature    = outside_temperature,
    Inside_temperature     = inside_temperature,
    Indiv_Water_mL         = indiv_water_ml,
    N_Days                 = n_day_vec,
    Total_hour             = total_hour
  )
}

# ---------------------------------------------------------
# BUILD FULL DATASET
# ---------------------------------------------------------

batch_start_dates <- as.Date("2023-01-01") + (seq_len(n_batches) - 1) * (n_days + 10)

D <- do.call(rbind, lapply(seq_len(n_batches), function(i){
  simulate_batch(lotcode = i, start_date = batch_start_dates[i])
}))

# ---------------------------------------------------------
# SAVE
# ---------------------------------------------------------

if(!dir.exists("data")) dir.create("data")

writexl::write_xlsx(D, output_file)

message("Simulated dataset written to: ", output_file)
message("Rows: ", nrow(D), " | Batches: ", n_batches, " | Days per batch: ", n_days)
