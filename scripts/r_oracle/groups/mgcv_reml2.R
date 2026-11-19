# mgcv: gam(y ~ s(x1, bs = "cr", k = k1) + s(x2, bs = "ps", k = k2), method = "REML"). Args: (n, k1, k2, what, idx, x1[n], x2[n], y[n]): what 0 the total edf, 2 fitted[idx].
# The REML score is not compared: gam's optimiser stops at a score tolerance, so the fits are compared to the tolerance of its stopping rule.
suppressMessages(library(mgcv))
cases <- list()
set.seed(20262311)
add <- function(args, want, rel = 1e-5, abs = 1e-8) cases[[length(cases) + 1]] <<- case("r2", args, want, rel = rel, abs = abs)
for (rep in 1:8) {
  n <- sample(80:130, 1); k1 <- sample(7:10, 1); k2 <- sample(7:10, 1)
  x1 <- round(runif(n, 0, 10), 3); x2 <- round(runif(n, -3, 3), 3)
  y <- round(sin(x1) + 0.4 * x2^2 / 3 + rnorm(n, 0, 0.4), 4)
  f <- gam(y ~ s(x1, bs = "cr", k = k1) + s(x2, bs = "ps", k = k2), method = "REML")
  hdr <- function(w, i) c(n, k1, k2, w, i, x1, x2, y)
  add(hdr(0, 0), sum(f$edf), rel = 3e-3)
  for (i in seq(1, n, by = 9)) add(hdr(2, i - 1), f$fitted.values[i], rel = 3e-3, abs = 3e-3)
}
emit("mgcv_reml2", "mgcv", list(cases))
