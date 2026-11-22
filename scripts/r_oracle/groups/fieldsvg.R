# fieldsvg: fields vgram (variogram, covariogram, correlogram; Euclidean and great-circle) with stats.bin summaries.
#   one "vg" case = args c(op, idx, type, lonlat, n, nbins, dmax, nbreaks, x row-major, y, breaks); ops are at the top of lib/e/algo/stat/fieldsvg.e
suppressMessages(library(fields)); options(warn = -1)
cases <- list()
set.seed(20262011)
one <- function(x, y, type, lonlat, nbins = 0, dmax = 0, breaks = NULL) {
  tp <- c("variogram", "covariogram", "correlogram")[type + 1]
  v <- vgram(x, y, lon.lat = lonlat == 1, dmax = if (dmax > 0) dmax else NULL, N = if (nbins > 0) nbins else NULL, breaks = breaks, type = tp)
  base <- c(type, lonlat, nrow(x), nbins, dmax, length(breaks), as.vector(t(x)), y, breaks)
  add <- function(op, idx, want) cases[[length(cases) + 1]] <<- case("vg", c(op, idx, base), want, rel = 1e-9, abs = 1e-12)
  m <- length(v$d)
  add(2, 0, m)
  for (j in unique(c(1, 2, round(m / 2), m - 1, m))) { add(0, j - 1, v$d[j]); add(1, j - 1, v$vgram[j]) }
  if (!is.null(v$stats)) {
    nb <- length(v$centers)
    for (j in seq_len(nb)) {
      if (v$stats[1, j] < 2) next
      add(3, j - 1, v$centers[j])
      for (s in 1:8) add(3 + s, j - 1, v$stats[s, j])
    }
  }
}
for (rep in 1:6) {
  n <- sample(12:30, 1)
  x <- cbind(runif(n, 0, 10), runif(n, 0, 6)); y <- sin(x[, 1]) + rnorm(n)
  type <- (rep - 1) %% 3
  one(x, y, type, 0)
  one(x, y, type, 0, nbins = sample(4:6, 1), dmax = if (rep %% 2 == 0) 8 else 0)
  one(x, y, type, 0, breaks = seq(0, 12, by = 3))
}
for (rep in 1:3) {
  n <- sample(10:20, 1)
  x <- cbind(runif(n, -110, -90), runif(n, 30, 45)); y <- rnorm(n) + x[, 2] * 0.1
  one(x, y, rep - 1, 1)
  one(x, y, rep - 1, 1, nbins = 5)
}
emit("fieldsvg", "fields", list(cases))
