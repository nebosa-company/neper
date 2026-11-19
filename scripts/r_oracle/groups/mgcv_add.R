# mgcv: an additive model of two smooths with given smoothing parameters, gam(y ~ s(x1, bs = "cr", k = k1) + s(x2, bs = "ps", k = k2), sp = c(sp1, sp2)).
# Args: (n, k1, k2, sp1, sp2, what, idx, x1[n], x2[n], y[n]): what 0 coef[idx], 1 fitted[idx], 2 the total edf, 3 the residual sum of squares.
suppressMessages(library(mgcv))
cases <- list()
set.seed(20262306)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("add", args, want, rel = 1e-7, abs = 1e-9)
for (rep in 1:10) {
  n <- sample(60:110, 1); k1 <- sample(6:10, 1); k2 <- sample(6:10, 1); sp1 <- 10^runif(1, -2, 1); sp2 <- 10^runif(1, -2, 1)
  x1 <- round(runif(n, 0, 10), 3); x2 <- round(runif(n, -3, 3), 3)
  y <- round(sin(x1) + 0.4 * x2^2 / 3 + rnorm(n, 0, 0.4), 4)
  f <- gam(y ~ s(x1, bs = "cr", k = k1) + s(x2, bs = "ps", k = k2), sp = c(sp1, sp2))
  hdr <- function(w, i) c(n, k1, k2, sp1, sp2, w, i, x1, x2, y)
  for (i in seq_along(f$coefficients)) add(hdr(0, i - 1), f$coefficients[i])
  for (i in seq(1, n, by = 5)) add(hdr(1, i - 1), f$fitted.values[i])
  add(hdr(2, 0), sum(f$edf)); add(hdr(3, 0), sum(f$residuals^2))
}
emit("mgcv_add", "mgcv", list(cases))
