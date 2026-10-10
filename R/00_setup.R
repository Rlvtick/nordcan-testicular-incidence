library(ggplot2)

# =============== Paths ===============

# knitting runs from the project root, running chunks in RStudio runs from R/.
# renv.lock marks the root, so this also resolves paths that do not exist yet,
# which a file-existence test cannot do
PROJECT_ROOT <- if (file.exists("renv.lock")) "." else ".."

stopifnot("cannot locate the project root from the working directory" =
            file.exists(file.path(PROJECT_ROOT, "renv.lock")))

# resolves a project-root-relative path, for reading and for writing alike
proj_file <- function(path) {
  file.path(PROJECT_ROOT, path)
}


# =============== Colours ===============

# fixed per country and never reassigned, so dropping one cannot repaint the
# others. Slots 1-5 of a palette checked for colour-vision deficiency
COUNTRY_COLORS <- c(
  Denmark = "#2a78d6",
  Finland = "#eb6834",
  Iceland = "#1baf7a",
  Norway  = "#eda100",
  Sweden  = "#e87ba4"
)

INK        <- "#0b0b0b"
INK_SOFT   <- "#52514e"
INK_MUTED  <- "#8a8984"
GRID       <- "#e6e5e1"


# =============== Chart Theme ===============

# shared look: centred bold title, bold axis titles, source line bottom right
theme_eda <- function() {
  theme_minimal(base_size = 12) +
    theme(
      plot.title   = element_text(colour = INK, face = "bold", size = 13,
                                  hjust = 0.5, margin = margin(b = 12)),
      plot.caption = element_text(colour = INK_MUTED, size = 9, hjust = 1,
                                  margin = margin(t = 14)),
      axis.title.x = element_text(colour = INK_SOFT, size = 10, face = "bold",
                                  margin = margin(t = 8)),
      axis.title.y = element_text(colour = INK_SOFT, size = 10, face = "bold",
                                  margin = margin(r = 8)),
      axis.text    = element_text(colour = INK_SOFT, size = 9),
      panel.grid.major = element_line(colour = GRID, linewidth = 0.3),
      panel.grid.minor = element_blank(),
      strip.text   = element_text(colour = INK, face = "bold", size = 10),
      plot.margin  = margin(t = 10, r = 14, b = 10, l = 10),
      legend.position = "none"
    )
}

# places the legend inside the panel, anchored to one corner
legend_corner <- function(x, y) {
  theme(legend.position = "inside",
        legend.position.inside = c(x, y),
        legend.justification = c(x, y),
        legend.title = element_blank(),
        legend.text = element_text(colour = INK_SOFT, size = 9),
        legend.background = element_rect(fill = "white", colour = GRID),
        legend.margin = margin(4, 6, 4, 6))
}

SOURCE_NOTE <- "Source: NORDCAN 2.0 (version 9.6 - 06.2026)"


# =============== Shared Data Facts ===============

# the 18 five-year bands the prepared data uses, written out independently so
# a factor's level order can be checked against something it did not build
EXPECTED_BANDS <- c(paste0(seq(0L, 80L, 5L), "-", seq(4L, 84L, 5L)), "85+")

N_COUNTRIES <- 5L
N_PERIODS   <- 7L
N_BANDS     <- 18L
