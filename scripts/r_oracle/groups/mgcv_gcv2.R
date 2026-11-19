# mgcv: gam(y ~ s(x1, bs = "cr", k = k1) + s(x2, bs = "ps", k = k2)) with both smoothing parameters chosen by GCV. Args: (n, k1, k2, what, idx, x1[n], x2[n], y[n]):
# what 0 the best GCV score, 1 the total edf, 2 fitted[idx] (the last two only when gam's own optimiser reached the best score).
# gam's Newton iteration sometimes stops at a local optimum with a worse score (the GCV surface has a flat valley), so the expected score is the best of gam's own and the
# best found by a grid over (log sp1, log sp2) in [-12, 12]^2 refined by Nelder-Mead on gam(..., sp = ); the number of such cases is printed.
suppressMessages(library(mgcv))
cases <- list()
set.seed(20262309)
add <- function(args, want, rel = 1e-5, abs = 1e-8) cases[[length(cases) + 1]] <<- case("g2", args, want, rel = rel, abs = abs)
worse <- 0
for (rep in 1:8) {
  n <- sample(80:130, 1); k1 <- sample(7:10, 1); k2 <- sample(7:10, 1)
  x1 <- round(runif(n, 0, 10), 3); x2 <- round(runif(n, -3, 3), 3)
  y <- round(sin(x1) + 0.4 * x2^2 / 3 + rnorm(n, 0, 0.4), 4)
  f <- gam(y ~ s(x1, bs = "cr", k = k1) + s(x2, bs = "ps", k = k2))
  sc <- function(rho) tryCatch(as.numeric(gam(y ~ s(x1, bs = "cr", k = k1) + s(x2, bs = "ps", k = k2), sp = exp(rho))$gcv.ubre), error = function(e) 1e300)
  grid <- expand.grid(a = seq(-12, 12, by = 2), b = seq(-12, 12, by = 2)); gv <- apply(grid, 1, sc); g0 <- as.numeric(grid[which.min(gv), ])
  o <- optim(g0, sc, method = "Nelder-Mead", control = list(reltol = 1e-12, maxit = 600))
  best <- min(as.numeric(f$gcv.ubre), o$value)
  hdr <- function(w, i) c(n, k1, k2, w, i, x1, x2, y)
  add(hdr(0, 0), best, rel = 1e-5)
  if (as.numeric(f$gcv.ubre) > best + 1e-5 * abs(best)) { worse <- worse + 1; next }
  add(hdr(1, 0), sum(f$edf), rel = 2e-3)
  for (i in seq(1, n, by = 9)) add(hdr(2, i - 1), f$fitted.values[i], rel = 2e-3, abs = 2e-3)
}
cat("gam stopped at a worse GCV optimum in", worse, "of 8 data sets\n")
emit("mgcv_gcv2", "mgcv", list(cases))
