# Predictive modelling of hourly water consumption in finishing pigs

Companion code repository for:

> Marroco et al. *Time Series Modelling of Water Consumption in Fattening Pigs.*

This repository contains the R code used to model hourly water consumption in
growing-finishing pigs using five approaches — Linear Regression, Random
Forest, XGBoost, a Neural Network (MLP), and a Dynamic Linear Model (DLM) —
under a leave-one-batch-out validation strategy within each production unit.

The original commercial dataset used in the study is **not publicly
available** (see *Data availability* in the paper). To allow anyone to run
the full pipeline and inspect how it works, this repository includes a
script that generates a **simulated example dataset** with the same
structure (circadian pattern, growth trend over the fattening period, and
occasional consumption spikes), on which all scripts below can be run
end-to-end.

## Repository structure

```
.
├── data/
│   └── simulate_data.R          # generates a synthetic example dataset
├── scripts/
│   ├── utils.R                  # shared functions (metrics, lags, features)
│   ├── 01_linear_regression.R   # baseline + extended (lagged) LR
│   ├── 02_random_forest.R
│   ├── 03_xgboost.R
│   ├── 04_neural_network.R
│   ├── 05_dlm.R                 # see "About the DLM script" below
│   └── 06_compile_results.R     # combines results, prints summary table + figures
└── outputs/                     # created automatically when scripts are run
```

## How to run

### 1. Set your working directory

Before running anything, R needs to know where the `repo` folder lives on
your computer, so that it can find `data/`, `scripts/`, etc.

**Option A — using code (in the RStudio console):**

```r
setwd("C:/Users/your_username/Downloads/repo")   # Windows example
setwd("/Users/your_username/Downloads/repo")     # Mac example
```

Use your own path, and use forward slashes `/` even on Windows. Check it
worked with:

```r
getwd()
```

**Option B — using the RStudio menu (no code needed):**
`Session` → `Set Working Directory` → `Choose Directory...` → select the
`repo` folder → `Open`.

### 2. Install the required packages (first time only)

```r
install.packages(c(
  "readxl", "writexl", "dplyr", "tidyr", "ggplot2",
  "randomForest", "xgboost", "nnet", "zoo"
))
```

This can take a couple of minutes the first time. If a package is already
installed, R will simply skip or reinstall it — no harm either way.

### 3. Generate the example dataset

```r
source("data/simulate_data.R")
```

You should see a message like `Simulated dataset written to:
data/Water_Database_simulated.xlsx`. If you see this, it worked.

### 4. Run the modelling scripts you want

Each script is self-contained and can be run independently, in any order
(you don't need to run all five):

```r
source("scripts/01_linear_regression.R")
source("scripts/02_random_forest.R")
source("scripts/03_xgboost.R")
source("scripts/04_neural_network.R")
```

You will see progress messages printed as each script runs (e.g.
`[Random Forest] building: Farm_1.0.1 | batch: 1`) — this is normal and
just shows it is working through each batch.

### 5. Combine the results into a summary table and figures

```r
source("scripts/06_compile_results.R")
```

This produces `outputs/summary_table.csv` (RMSE/MAE per model, analogous
to Table 2 in the paper), `outputs/Figure_RMSE_comparison.png`, and
`outputs/Figure_observed_vs_predicted.png`. Any model whose output files
are not found is skipped automatically, so you do not need to run all
five scripts to use this step.

### 6. Check the results

Open the `outputs` folder in your normal file explorer (Finder / File
Explorer) — no R needed for this step. Open the `.csv` in Excel and the
`.png` files like any image.

### Running from the command line instead

If you prefer not to use an interactive R session:

```bash
Rscript data/simulate_data.R
Rscript scripts/01_linear_regression.R
Rscript scripts/02_random_forest.R
Rscript scripts/03_xgboost.R
Rscript scripts/04_neural_network.R
Rscript scripts/06_compile_results.R
```

### Troubleshooting

| Error message | Likely cause |
|---|---|
| `cannot open file '...': No such file or directory` | Your working directory (Step 1) isn't pointing at the `repo` folder. Check with `getwd()`. |
| `there is no package called '...'` | That package wasn't installed. Re-run Step 2, adding the missing package name. |
| `DLM dependencies not found...` (when running `05_dlm.R`) | Expected — see "About the DLM script" below. This is not an error; the script skips DLM automatically and the rest of the pipeline is unaffected. |

## Using your own data

To apply this pipeline to your own dataset, replace the `data_file` path at
the top of each modelling script with your own file. Your data should
contain at least the following columns (see `data/simulate_data.R` for the
exact structure expected):

| Column | Description |
|---|---|
| `Building_name` | Production unit identifier |
| `lotcode` | Batch identifier (used for leave-one-batch-out validation) |
| `Date` | Date of the observation |
| `Hour` | Hour of the day (0-23) |
| `num_animals` | Number of animals present in the unit |
| `water_L` | Hourly water consumption (L/hour) — the response variable |
| `N_Days` | Fattening day (1, 2, 3, ...) |
| `Total_hour` | Sequential hour index within the batch |

## About the DLM script

`scripts/05_dlm.R` implements the Dynamic Linear Model described in the
paper, but depends on a set of custom state-space modelling functions
(implementing the framework of Madsen & Kristensen, 2005) that were
developed for teaching purposes and are **not included in this
repository**. Running this script without them will print a message
explaining what is missing and skip the DLM step; scripts 01-04 and 06 do
not depend on it in any way. If you have access to these functions, place
them in a local `dlm_dependencies/` folder as described in the header of
the script.

## Required R packages

```r
install.packages(c(
  "readxl", "writexl", "dplyr", "tidyr", "ggplot2",
  "randomForest", "xgboost", "nnet", "zoo"
))
```

## Citation

If you use this code, please cite the original publication:

> Marroco et al. *Time Series Modelling of Water Consumption in Fattening
> Pigs.* [add full citation / DOI once available]

## License

This repository is released under the MIT License — see [`LICENSE`](LICENSE)
for details.