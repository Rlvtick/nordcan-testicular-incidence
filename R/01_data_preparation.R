library(readr)
library(readxl)
library(dplyr)
library(tidyr)

STUDY_COUNTRIES <- c("Denmark", "Finland", "Iceland", "Norway", "Sweden")

PERIODS <- c("1990-1994", "1995-1999", "2000-2004", "2005-2009",
             "2010-2014", "2015-2019", "2020-2024")

# Excel stores age columns as numbers, so readxl names them "0.0".."85.0"
AGE_COLS <- paste0(seq(0, 85, 5), ".0")

# NORDCAN population is an average annual figure, not 5-year person-years.
# Dropping this silently inflates every rate 5x - no error, output still looks fine
PERIOD_YEARS <- 5

CRUDE_TOL <- 1e-3

N_EXPECTED_ROWS <- length(STUDY_COUNTRIES) * length(PERIODS) * length(AGE_COLS)


# =============== Read Data ===============

# Reads one workbook (numbers or populations) across all 7 period sheets
read_age_workbook <- function(path) {
  sheets <- lapply(PERIODS, function(p) {
    d <- read_excel(path, sheet = p)

    # column A is headed "Population" but holds the country name; B is the all-ages total
    names(d)[1:2] <- c("country", "total")

    # keeps the 5 study countries, drops aggregates/Faroe/Greenland/junk rows
    # whitelist not blacklist: an unexpected label is excluded, never silently admitted
    d <- d[d$country %in% STUDY_COUNTRIES, ]

    # a stray "\" cell in numbers/1990-1994 turns one age column into character otherwise
    d[AGE_COLS] <- lapply(d[AGE_COLS], as.numeric)
    d$total <- as.numeric(d$total)

    d$period <- p
    d[c("country", "period", "total", AGE_COLS)]
  })
  bind_rows(sheets)
}

# Reshapes a workbook from wide (one column per age band) to long
to_long <- function(wb, value_col) {
  wb |>
    select(country, period, all_of(AGE_COLS)) |>
    pivot_longer(all_of(AGE_COLS), names_to = "age_col", values_to = value_col)
}

# paths are relative - run from the project root: Rscript R/01_data_preparation.R
numbers_wb <- read_age_workbook("data/raw/dataset_age-specific_numbers.xlsx")
pops_wb    <- read_age_workbook("data/raw/dataset_populations.xlsx")

published <- bind_rows(lapply(PERIODS, function(p) {
  read_csv(file.path("data", "raw", paste0("dataset-inc-males-", p, ".csv")),
           show_col_types = FALSE)
})) |>
  filter(Label %in% STUDY_COUNTRIES) |>
  transmute(
    country     = Label,
    period      = Year,
    cases_total = as.integer(Numbers),
    crude_rate  = `Crude rate`,
    asr_eu2013  = `ASR (European 2013)`
  ) |>
  arrange(country, period)


# =============== Merging the Data ===============

# full_join so a missing country-period shows up as NA instead of vanishing
age_specific <- full_join(
    to_long(numbers_wb, "cases"),
    to_long(pops_wb, "pop_annual_mean"),
    by = c("country", "period", "age_col")
  ) |>
  mutate(
    age_start       = as.integer(sub("\\.0$", "", age_col)),
    age_band        = ifelse(age_start == 85, "85+",
                             paste0(age_start, "-", age_start + 4)),
    period_mid      = as.integer(substr(period, 1, 4)) + 2,
    cases           = as.integer(cases),
    pop_annual_mean = as.integer(pop_annual_mean),
    person_years    = as.numeric(pop_annual_mean) * PERIOD_YEARS
  ) |>
  select(country, period, period_mid, age_band, age_start,
         cases, pop_annual_mean, person_years) |>
  arrange(country, period, age_start)


# =============== Validate ===============

stopifnot(
  "merged row count is not countries x periods x age bands" =
    nrow(age_specific) == N_EXPECTED_ROWS,
  "duplicate country/period/age-band rows" =
    anyDuplicated(age_specific[c("country", "period", "age_start")]) == 0,
  "missing case or population values after merge" =
    !anyNA(age_specific$cases) && !anyNA(age_specific$pop_annual_mean),
  "zero or negative population would break rate denominators" =
    all(age_specific$pop_annual_mean > 0),
  "age bands are not identical across every country-period" =
    all(tapply(age_specific$age_start,
               paste(age_specific$country, age_specific$period),
               function(x) identical(sort(x), seq(0L, 85L, 5L)))),
  "published benchmark table is not 5 countries x 7 periods" =
    nrow(published) == length(STUDY_COUNTRIES) * length(PERIODS),
  "duplicate country/period in the published benchmark table" =
    anyDuplicated(published[c("country", "period")]) == 0,
  "published benchmark table has missing values" =
    !anyNA(published)
)

totals <- age_specific |>
  group_by(country, period) |>
  summarise(cases_sum = sum(cases),
            pop_sum   = sum(pop_annual_mean),
            py_sum    = sum(person_years),
            .groups   = "drop") |>
  left_join(select(numbers_wb, country, period, wb_cases = total),
            by = c("country", "period")) |>
  left_join(select(pops_wb, country, period, wb_pop = total),
            by = c("country", "period")) |>
  left_join(published, by = c("country", "period")) |>
  mutate(crude_computed = cases_sum / py_sum * 1e5,
         crude_diff     = abs(crude_computed - crude_rate))

stopifnot(
  "joining the source totals changed the country-period row count" =
    nrow(totals) == length(STUDY_COUNTRIES) * length(PERIODS),
  "age-band cases do not sum to the workbook total" =
    all(totals$cases_sum == totals$wb_cases),
  "age-band populations do not sum to the workbook total" =
    all(totals$pop_sum == totals$wb_pop),
  "age-band cases do not sum to NORDCAN's published case total" =
    all(totals$cases_sum == totals$cases_total),
  "computed crude rate disagrees with NORDCAN's published crude rate" =
    max(totals$crude_diff) < CRUDE_TOL
)

# rates.xlsx came from NORDCAN's download button, unlike the copy-pasted numbers/
# populations - only witness on age-band alignment. Display-rounded: never output it
rate_check <- to_long(
    read_age_workbook("data/raw/dataset_age-specific_rates.xlsx"),
    "nordcan_rate"
  ) |>
  inner_join(
    transmute(age_specific,
              country, period,
              age_col       = paste0(age_start, ".0"),
              computed_rate = cases / person_years * 1e5),
    by = c("country", "period", "age_col")
  ) |>
  mutate(
    # NORDCAN rounds to 1 decimal at/above 1.0, 2 decimals below - match it exactly.
    # An equality check, not a tolerance: nothing to calibrate, nothing to drift
    rate_rounded = ifelse(nordcan_rate < 1,
                          round(computed_rate, 2),
                          round(computed_rate, 1)),
    rate_agrees  = abs(rate_rounded - nordcan_rate) < 1e-9
  )

stopifnot(
  "age-specific rate check did not cover every row" =
    nrow(rate_check) == N_EXPECTED_ROWS,
  "computed age-specific rates do not reproduce NORDCAN's published rates" =
    all(rate_check$rate_agrees)
)


# =============== Write ===============

dir.create("data/processed", showWarnings = FALSE, recursive = TRUE)
write_csv(age_specific, "data/processed/testis_age_specific.csv")
write_csv(published,    "data/processed/nordcan_published.csv")

cat("Data Preparation complete.\n\n")
cat(sprintf("  crude rate      max diff %.2e  (tolerance %.0e)\n",
            max(totals$crude_diff), CRUDE_TOL))
cat(sprintf("  age-band rates  %d / %d reproduce NORDCAN exactly when rounded\n\n",
            sum(rate_check$rate_agrees), nrow(rate_check)))
cat(sprintf("  data/processed/testis_age_specific.csv  %d rows\n",
            nrow(age_specific)))
cat(sprintf("  data/processed/nordcan_published.csv    %d rows\n",
            nrow(published)))
