# R side of the chart benchmark: ggplot2, base R graphics and lattice; mirrors chart_bench.e and mpl_bench.py.
#
# Each chart: a 1,000-point line, 200 square scatter markers, a y grid with tick labels at -2, 0 and 2 and a title, 360x240
# pixels (3.6 x 2.4 in at 100 dpi), written to a file as SVG with the text kept as text (svglite) and as PNG (the png() device),
# 200 charts per pass. Prints the same lines as the other two programs, one per package and format:
#   name charts milliseconds bytes
# e.g. `ggplot2_svg 200 3120.5 9400000`, `base_png ...`, `lattice_svg ...`, and `import 0 <ms> 0` for loading the packages.
#
# Needs R with the packages ggplot2, lattice and svglite. UNVERIFIED on this repository's benchmark host, which has no R
# (L162): run `Rscript benchmarks/charts/r_bench.R [first-chart.png]` and `python benchmarks/charts/run.py <neper-self> 9`.

started <- proc.time()[["elapsed"]]
suppressPackageStartupMessages({
  library(ggplot2)
  library(lattice)
  library(svglite)
})
import_ms <- (proc.time()[["elapsed"]] - started) * 1000

CHARTS <- 200L
POINTS <- 1000L
MOD <- 2147483648
MUL <- 1103515245

# (state * 1103515245 + 12345) %% 2^31 exactly: the product does not fit a double, so split the state into 16-bit halves.
lcg_next <- function(state) {
  hi <- state %/% 65536
  lo <- state %% 65536
  (((hi * MUL) %% MOD) * 65536 + (lo * MUL) %% MOD + 12345) %% MOD
}

chart_data <- function(index) {
  state <- 1 + index
  frequency <- 1.0 + (index %% 5) * 0.2
  x <- numeric(POINTS)
  y <- numeric(POINTS)
  for (i in seq_len(POINTS)) {
    state <- lcg_next(state)
    noise <- (state / MOD - 0.5) * 0.3
    xi <- 10.0 * (i - 1) / 999.0
    x[i] <- xi
    y[i] <- sin(xi * frequency) + noise
  }
  pick <- seq(1L, POINTS, by = 5L)
  list(x = x, y = y, sx = x[pick], sy = y[pick] + 0.5)
}

LINE <- rgb(0, 114, 178, maxColorValue = 255)
MARK <- rgb(195, 86, 0, maxColorValue = 255)
GRID <- rgb(0.84, 0.87, 0.92)
TITLE <- "Signal with samples"

draw_base <- function(d) {
  par(mar = c(0.6, 2.2, 1.6, 0.4), mgp = c(1, 0.4, 0), cex.axis = 0.58, cex.main = 0.58, tck = 0)
  plot(d$x, d$y, type = "n", xlim = c(0, 10), ylim = c(-2, 2.5), xaxt = "n", yaxt = "n", xlab = "", ylab = "", bty = "n",
       xaxs = "i", yaxs = "i", main = TITLE, font.main = 1)
  abline(h = c(-2, 0, 2), col = GRID)
  lines(d$x, d$y, col = LINE, lwd = 1.44)
  points(d$sx, d$sy, pch = 15, col = MARK, cex = 0.5)
  axis(2, at = c(-2, 0, 2), tick = FALSE, las = 1)
}

draw_ggplot <- function(d) {
  line <- data.frame(x = d$x, y = d$y)
  marks <- data.frame(x = d$sx, y = d$sy)
  ggplot() +
    geom_line(data = line, aes(x, y), colour = LINE, linewidth = 0.5) +
    geom_point(data = marks, aes(x, y), shape = 15, colour = MARK, size = 0.7) +
    scale_x_continuous(limits = c(0, 10), breaks = NULL, expand = c(0, 0)) +
    scale_y_continuous(limits = c(-2, 2.5), breaks = c(-2, 0, 2), expand = c(0, 0)) +
    labs(title = TITLE, x = NULL, y = NULL) +
    theme_minimal(base_size = 6) +
    theme(panel.grid.minor = element_blank(), panel.grid.major.x = element_blank(),
          panel.grid.major.y = element_line(colour = GRID), plot.title = element_text(hjust = 0.5, size = 6),
          plot.margin = margin(2, 2, 2, 2))
}

draw_lattice <- function(d) {
  p <- xyplot(y ~ x, data = data.frame(x = d$x, y = d$y), xlim = c(0, 10), ylim = c(-2, 2.5), main = list(TITLE, cex = 0.58),
              xlab = NULL, ylab = NULL,
              scales = list(x = list(draw = FALSE), y = list(at = c(-2, 0, 2), cex = 0.58)),
              panel = function(x, y, ...) {
                panel.abline(h = c(-2, 0, 2), col = GRID)
                panel.lines(x, y, col = LINE, lwd = 1.44)
                panel.points(d$sx, d$sy, pch = 15, col = MARK, cex = 0.5)
              })
  print(p)
}

chart <- function(package, d) {
  if (package == "base") draw_base(d) else if (package == "ggplot2") print(draw_ggplot(d)) else draw_lattice(d)
}

run <- function(package, format, first = NULL) {
  total <- 0
  begin <- proc.time()[["elapsed"]]
  for (j in seq_len(CHARTS) - 1L) {
    path <- tempfile(fileext = paste0(".", format))
    if (format == "svg") {
      svglite::svglite(path, width = 3.6, height = 2.4)
    } else {
      png(path, width = 360, height = 240, res = 100)
    }
    chart(package, chart_data(j))
    invisible(dev.off())
    total <- total + file.size(path)
    if (j == 0L && format == "png" && package == "ggplot2" && !is.null(first)) file.copy(path, first, overwrite = TRUE)
    unlink(path)
  }
  cat(sprintf("%s_%s %d %.3f %d\n", package, format, CHARTS, (proc.time()[["elapsed"]] - begin) * 1000, as.integer(total)))
}

args <- commandArgs(trailingOnly = TRUE)
first <- if (length(args) > 0) args[1] else NULL
cat(sprintf("import 0 %.3f 0\n", import_ms))
for (package in c("ggplot2", "base", "lattice")) {
  run(package, "svg")
  run(package, "png", first)
}
