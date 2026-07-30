# =========================================================
# 06 - COMPILE RESULTS
# Combines the outputs of scripts 01-05, prints a summary
# table analogous to Table 2 in the paper, and produces two
# example figures (RMSE comparison, observed vs predicted).
# Models whose .rds files are not found (e.g. DLM, if its
# dependencies were not available) are skipped automatically.
# =========================================================

library(dplyr)
library(tidyr)
library(ggplot2)

output_dir <- "outputs"

model_files <- list(
  "LR"  = c(output_dir, "results_LR.rds",  "hourly_results_LR.rds"),
  "RF"  = c(output_dir, "results_RF.rds",  "hourly_results_RF.rds"),
  "XGB" = c(output_dir, "results_XGB.rds", "hourly_results_XGB.rds"),
  "NN"  = c(output_dir, "results_NN.rds",  "hourly_results_NN.rds"),
  "DLM" = c(output_dir, "results_DLM.rds", "hourly_results_DLM.rds")
)

model_labels <- c(
  "LR_baseline" = "bLR",
  "LR_extended" = "lLR",
  "RF"  = "Random Forest",
  "XGB" = "XGBoost",
  "NN"  = "Neural Network",
  "DLM" = "DLM"
)

# Same colour-per-model mapping used in the paper's figures (lLR uses the
# same hue as "Linear Regression" there; bLR is a lighter tint of that
# same hue, so both read as "the same family" of model but stay distinct).
model_colors <- c(
  "bLR"            = "#CCCE73",
  "lLR"            = "#A3A500",
  "Random Forest"  = "#E76BF3",
  "XGBoost"        = "#00B0F6",
  "Neural Network" = "#00BF7D",
  "DLM"            = "#F8766D"
)

# ---------------------------------------------------------
# LOAD AVAILABLE RESULTS
# ---------------------------------------------------------

results_list <- list()
hourly_list  <- list()

for(m in names(model_files)){
  
  f <- model_files[[m]]
  summary_path <- file.path(f[1], f[2])
  hourly_path  <- file.path(f[1], f[3])
  
  if(file.exists(summary_path) && file.exists(hourly_path)){
    
    r <- readRDS(summary_path)
    h <- readRDS(hourly_path)
    
    # LR script stores its own Model column (baseline/extended);
    # the other scripts do not, so it is added here.
    if(!"Model" %in% colnames(r)) r$Model <- m
    if(!"Model" %in% colnames(h)) h$Model <- m
    
    results_list[[m]] <- r
    hourly_list[[m]]  <- h
    
  } else {
    message("Skipping ", m, ": results not found in '", output_dir, "/' ",
            "(run the corresponding script first).")
  }
}

if(length(results_list) == 0){
  stop("No model results found in '", output_dir, "'. Run scripts 01-05 first.")
}

all_results        <- bind_rows(results_list)
hourly_results_all <- bind_rows(hourly_list)

all_results$Model_label        <- recode(all_results$Model, !!!model_labels)
hourly_results_all$Model_label <- recode(hourly_results_all$Model, !!!model_labels)

write.csv(all_results, file.path(output_dir, "all_results_combined.csv"), row.names = FALSE)

# ---------------------------------------------------------
# SUMMARY TABLE (analogous to Table 2 in the paper)
# ---------------------------------------------------------

summary_table <- all_results %>%
  group_by(Model_label) %>%
  summarise(
    RMSE_mean = mean(RMSE, na.rm = TRUE),
    RMSE_sd   = sd(RMSE, na.rm = TRUE),
    MAE_mean  = mean(MAE, na.rm = TRUE),
    MAE_sd    = sd(MAE, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(RMSE_mean) %>%
  mutate(
    RMSE = paste0(round(RMSE_mean, 2), " \u00b1 ", round(RMSE_sd, 2)),
    MAE  = paste0(round(MAE_mean, 2),  " \u00b1 ", round(MAE_sd, 2))
  ) %>%
  select(Model = Model_label, RMSE, MAE)

print(summary_table)

write.csv(summary_table, file.path(output_dir, "summary_table.csv"), row.names = FALSE)

# ---------------------------------------------------------
# FIGURE 1 - RMSE COMPARISON ACROSS MODELS
# ---------------------------------------------------------

p_rmse <- ggplot(all_results, aes(x = Model_label, y = RMSE, fill = Model_label)) +
  geom_boxplot(outlier.shape = NA) +
  geom_jitter(width = 0.15, alpha = 0.6) +
  scale_fill_manual(values = model_colors) +
  guides(fill = "none") +   # colour reinforces the x-axis category
  theme_minimal() +
  labs(title = "RMSE across modelling approaches (example dataset)",
       x = "", y = "RMSE (L/hour)") +
  theme(axis.text.x = element_text(angle = 25, hjust = 1))

ggsave(file.path(output_dir, "Figure_RMSE_comparison.png"),
       p_rmse, width = 8, height = 6, dpi = 300)

# ---------------------------------------------------------
# FIGURE 2 - OBSERVED VS PREDICTED, ONE EXAMPLE BATCH
# Automatically picks the first available building/batch
# common to all loaded models
# ---------------------------------------------------------

example_building <- hourly_results_all$Building_name[1]
example_batch    <- hourly_results_all$Test.set[1]

df_example <- hourly_results_all %>%
  filter(Building_name == example_building, Test.set == example_batch)

p_example <- ggplot(df_example, aes(x = Total_hour)) +
  geom_line(aes(y = Real), color = "navy", linewidth = 0.9) +
  geom_line(aes(y = Pred, color = Model_label), linewidth = 0.6, alpha = 0.8) +
  scale_color_manual(values = model_colors) +
  facet_wrap(~ Model_label, ncol = 1, scales = "free_y") +
  theme_minimal() +
  labs(
    title = paste0("Observed (navy) vs predicted values\n", example_building, " | batch ", example_batch),
    x = "Total hour", y = "Water consumption (L/hour)", color = ""
  )

ggsave(file.path(output_dir, "Figure_observed_vs_predicted.png"),
       p_example, width = 9, height = 2.5 * length(unique(df_example$Model_label)),
       dpi = 300, limitsize = FALSE)

message("Compilation completed. Table and figures saved in: ", output_dir)