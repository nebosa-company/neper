# mgcv: gam(y ~ s(x, bs = "tp", k = k)) with GCV selection of the smoothing parameter. The thin-plate regression spline basis differs from the port's by a reparametrisation (signs
# and scale of the columns), so the quantities compared are the ones that do not depend on it: the GCV score at the optimum, the total edf and the fitted values.
# Args: (n, k, what, idx, x[n], y[n]): what 0 the GCV score, 1 the total edf, 2 fitted[idx].
suppressMessages(library(mgcv))
cases <- list()
set.seed(20262310)
add <- function(args, want, rel = 1e-5, abs = 1e-8) cases[[length(cases) + 1]] <<- case("tp", args, want, rel = rel, abs = abs)
for (rep in 1:10) {
  n <- sample(40:90, 1); k <- sample(6:14, 1)
  x <- sort(round(runif(n, 0, 10), 3)); y <- round(sin(x) + 0.3 * x + rnorm(n, 0, 0.4), 4)
  f <- gam(y ~ s(x, bs = "tp", k = k))
  sc <- function(rho) tryCatch(as.numeric(gam(y ~ s(x, bs = "tp", k = k), sp = exp(rho))$gcv.ubre), error = function(e) 1e300)
  gr <- seq(-15, 15, by = 1); gv <- sapply(gr, sc); j <- which.min(gv)
  best <- min(as.numeric(f$gcv.ubre), optimize(sc, c(gr[max(j - 1, 1)], gr[min(j + 1, length(gr))]), tol = 1e-10)$objective)
  hdr <- function(w, i) c(n, k, w, i, x, y)
  add(hdr(0, 0), best, rel = 1e-6)
  if (as.numeric(f$gcv.ubre) > best + 1e-6 * abs(best)) next
  add(hdr(1, 0), sum(f$edf), rel = 2e-3)
  for (i in seq(1, n, by = 6)) add(hdr(2, i - 1), f$fitted.values[i], rel = 2e-3, abs = 2e-3)
}
emit("mgcv_tp", "mgcv", list(cases))
