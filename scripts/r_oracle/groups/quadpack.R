# R integrate() against e.math.quadpack (qags on a finite range, qagi on an infinite one): the value, the abs.error and the number of subdivisions.
#   args: (kind, lo, hi, what) with what 0 value, 1 abs.error, 2 subdivisions; kinds 0..5 finite, 6..8 infinite (lo, hi give the range, +-Inf as +-1e300)
suppressMessages(invisible(NULL))
cases <- list()
fs <- list(function(x) exp(-x^2 / 2) / sqrt(2 * pi), function(x) x * log(x), function(x) sin(x) / (1 + x^2), function(x) 1 / sqrt(x),
           function(x) abs(x - 0.3), function(x) cos(50 * x), function(x) exp(-x), function(x) 1 / (1 + x^2), function(x) exp(x))
rng <- list(c(-1.5, 2), c(0, 1), c(0, 7), c(0, 1), c(0, 1), c(0, 2), c(0, Inf), c(-Inf, Inf), c(-Inf, 1))
for (k in seq_along(fs)) {
  r <- integrate(fs[[k]], rng[[k]][1], rng[[k]][2])
  lo <- max(min(rng[[k]][1], 1e300), -1e300); hi <- max(min(rng[[k]][2], 1e300), -1e300)
  cases[[length(cases) + 1]] <- case("q", c(k - 1, lo, hi, 0), r$value, rel = 1e-10, abs = 1e-13)
  cases[[length(cases) + 1]] <- case("q", c(k - 1, lo, hi, 1), r$abs.error, rel = 1e-6, abs = 1e-18)
  cases[[length(cases) + 1]] <- case("q", c(k - 1, lo, hi, 2), r$subdivisions, rel = 0, abs = 0)
}
emit("quadpack", "base", list(cases))
