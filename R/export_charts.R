library(rmarkdown)

# =============== Why This Works The Way It Does ===============

# The charts are defined inside the reports, not here. Copying their code into
# this script would leave two versions to keep in step, which is the problem
# 00_setup.R exists to avoid. Instead each report is rendered to a throwaway
# location with self_contained turned off, which makes knitr write every figure
# out as a PNG, and those files are collected. The exported images are the same
# ones the published reports embed, because they come from the same render.

source(if (file.exists("R/00_setup.R")) "R/00_setup.R" else "00_setup.R")

REPORTS <- c("02_eda", "03_modeling")

# one entry per report: how many figures it should produce
EXPECTED_FIGURES <- c(`02_eda` = 6L, `03_modeling` = 3L)

OUT_DIR <- proj_file("output/figures")


# =============== Export ===============

# renders one report to a temporary place and returns the figure files knitr
# left behind, newest render only
figures_from <- function(report) {
  tmp <- file.path(tempdir(), paste0("export-", report))
  unlink(tmp, recursive = TRUE)
  dir.create(tmp, recursive = TRUE, showWarnings = FALSE)

  suppressMessages(render(
    proj_file(file.path("R", paste0(report, ".Rmd"))),
    output_file    = file.path(tmp, "probe.html"),
    output_options = list(self_contained = FALSE),
    quiet          = TRUE))

  # knitr puts chart PNGs under figure-html; everything else in there is theme
  # furniture from the HTML template
  found <- list.files(tmp, pattern = "[.]png$", recursive = TRUE,
                      full.names = TRUE)
  found[grepl("figure-html", found, fixed = TRUE)]
}

dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
invisible(file.remove(list.files(OUT_DIR, pattern = "[.]png$",
                                 full.names = TRUE)))

for (report in REPORTS) {
  figs <- figures_from(report)

  stopifnot(
    "a report produced a different number of charts than expected" =
      length(figs) == EXPECTED_FIGURES[[report]])

  # chunk labels already name these well, so keep them rather than maintaining
  # a lookup that would go stale the moment a chunk is renamed. The report
  # number goes in front so the files sort in reading order
  stem <- sub("-1[.]png$", ".png", basename(figs))
  dest <- file.path(OUT_DIR, paste0(sub("_.*$", "", report), "-", stem))

  stopifnot("two charts would be written to the same filename" =
              anyDuplicated(dest) == 0)

  file.copy(figs, dest, overwrite = TRUE)
}


# =============== Confirm ===============

written <- list.files(OUT_DIR, pattern = "[.]png$")

stopifnot(
  "the number of exported charts does not match the reports" =
    length(written) == sum(EXPECTED_FIGURES))

cat("Charts exported to output/figures:\n")
cat(paste0("  ", written, collapse = "\n"), "\n")
