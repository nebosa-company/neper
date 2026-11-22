# fieldskrig: fields Tps and Krig (Matern, exponential) at a fixed lambda.
#   one "fk" case = args c(op, idx, ctype, m, lambda, theta, nu, n, d, nq, x row-major, y, xq row-major); op meanings are at the top of lib/e/algo/stat/fieldskrig.R
suppressMessages(library(fields)); options(warn = -1)
cases <- list()
set.seed(20262010)
rows <- function(M) as.vector(t(as.matrix(M)))
one <- function(ctype, m, lambda, theta, nu, x, y, xq, fit, method = 0) {
  x <- as.matrix(x); xq <- as.matrix(xq); n <- nrow(x); d <- ncol(x); nq <- nrow(xq)
  base <- c(ctype, m, lambda, theta, nu, n, d, nq, method, rows(x), y, rows(xq))
  add <- function(op, idx, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case("fk", c(op, idx, base), want, rel = rel, abs = 1e-11)
  nt <- ncol(fields.mkpoly(x, m))
  if (m == 2) for (j in seq_len(nt)) add(0, j - 1, fit$d[j])
  for (j in c(1, 2, n)) add(1, j - 1, fit$c[j], 1e-9)
  lam <- fit$lambda.est[c("user", "GCV", "REML")[method + 1], ]
  if (method > 0) add(10, 0, fit$lambda)
  add(2, 0, lam["trA"]); add(3, 0, lam["GCV"]); add(4, 0, lam["tauHat"])
  add(5, 0, fit$rhohat); add(6, 0, fit$tauHat.MLE)
  for (j in c(1, 2)) add(7, j - 1, fit$fitted.values[j])
  pr <- predict(fit, xq)
  for (j in seq_len(nq)) add(8, j - 1, pr[j])
  se <- predictSE(fit, xq)
  for (j in seq_len(nq)) add(9, j - 1, se[j])
}
mk <- function(n, d) {
  x <- matrix(runif(n * d, 0, 10), n, d) * rep(runif(d, 0.5, 2), each = n) + rep(runif(d, -3, 3), each = n)
  y <- sin(x[, 1]) + (if (d > 1) x[, 2] * 0.3 else 0) + rnorm(n, 0, 0.3)
  list(x = x, y = y, xq = x[seq_len(3), , drop = FALSE] + matrix(runif(3 * d, -0.3, 0.3), 3, d))
}
for (cfg in list(c(1, 2, 14), c(2, 2, 16), c(2, 2, 12), c(3, 2, 20), c(2, 3, 18), c(1, 3, 15), c(4, 3, 30))) {
  d <- cfg[1]; m <- cfg[2]; n <- cfg[3]
  D <- mk(n, d); lam <- 10^runif(1, -3, 0)
  one(0, m, lam, 0, 0, D$x, D$y, D$xq, Tps(D$x, D$y, m = m, lambda = lam, GCV = TRUE))
}
for (rep in 1:3) {
  d <- c(1, 2, 2)[rep]; D <- mk(c(14, 16, 18)[rep], d); lam <- 10^runif(1, -2, 0.5); th <- runif(1, 1, 5)
  one(2, 2, lam, th, 0, D$x, D$y, D$xq, Krig(D$x, D$y, Covariance = "Exponential", theta = th, lambda = lam, GCV = TRUE))
  for (nu in c(0.5, 1.5, runif(1, 0.7, 3))) {
    one(1, 2, lam, th, nu, D$x, D$y, D$xq, Krig(D$x, D$y, Covariance = "Matern", theta = th, smoothness = nu, lambda = lam, GCV = TRUE))
  }
}
# fastTps / mKrig with the Wendland covariance (k = 2, two dimensions) at a fixed aRange and lambda
mone <- function(x, y, xq, th, lam) {
  fit <- fastTps(x, y, m = 2, aRange = th, lambda = lam)
  n <- nrow(x); nq <- nrow(xq)
  base <- c(3, 2, lam, th, 0, n, 2, nq, 0, rows(x), y, rows(xq))
  add <- function(op, idx, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case("fk", c(op, idx, base), want, rel = rel, abs = 1e-11)
  for (j in 1:3) add(0, j - 1, fit$d[j])
  for (j in c(1, 2, n)) add(1, j - 1, fit$c.coef[j])
  add(5, 0, fit$rho.MLE.FULL); add(6, 0, sqrt(lam * fit$rho.MLE.FULL)); add(12, 0, fit$lnProfileLike.FULL)
  for (j in c(1, 2)) add(7, j - 1, fit$fitted.values[j])
  pr <- predict(fit, xq); se <- predictSE(fit, xq)
  for (j in seq_len(nq)) { add(8, j - 1, pr[j]); add(14, j - 1, se[j]) }
}
for (rep in 1:4) {
  n <- c(20, 25, 30, 35)[rep]; D <- mk(n, 2)
  mone(D$x, D$y, D$xq, runif(1, 3, 8), 10^runif(1, -2.5, 0))
}
# lambda chosen by GCV (Tps default) and REML / GCV (Krig)
for (cfg in list(c(1, 2, 18), c(2, 2, 20), c(2, 2, 24), c(3, 2, 30), c(2, 3, 26))) {
  d <- cfg[1]; m <- cfg[2]; n <- cfg[3]
  D <- mk(n, d)
  one(0, m, 0, 0, 0, D$x, D$y, D$xq, Tps(D$x, D$y, m = m), 1)
}
for (rep in 1:4) {
  d <- c(1, 2, 2, 2)[rep]; D <- mk(c(20, 24, 22, 28)[rep], d); th <- runif(1, 1, 5); nu <- c(0.5, 1.5, 2.5, runif(1, 0.7, 3))[rep]
  one(1, 2, 0, th, nu, D$x, D$y, D$xq, Krig(D$x, D$y, Covariance = "Matern", theta = th, smoothness = nu), 2)
  one(1, 2, 0, th, nu, D$x, D$y, D$xq, Krig(D$x, D$y, Covariance = "Matern", theta = th, smoothness = nu, method = "GCV"), 1)
}
# predictSurface (extrap = FALSE): the convex hull mask (op 15) and the predicted surface (op 8) on a grid, the grid reaching past the data; a Tps and a Krig fit on simulated points
# and a Tps fit on a subset of the bundled ozone2 stations
surf <- function(ctype, m, lambda, theta, nu, x, y, fit, method = 0) {
  gx <- seq(min(x[, 1]) - 0.1 * diff(range(x[, 1])), max(x[, 1]) + 0.1 * diff(range(x[, 1])), length.out = 5)
  gy <- seq(min(x[, 2]) - 0.1 * diff(range(x[, 2])), max(x[, 2]) + 0.1 * diff(range(x[, 2])), length.out = 4)
  xq <- as.matrix(expand.grid(gx, gy)); n <- nrow(x); nq <- nrow(xq)
  base <- c(ctype, m, lambda, theta, nu, n, 2, nq, method, rows(x), y, rows(xq))
  add <- function(op, idx, want) cases[[length(cases) + 1]] <<- case("fk", c(op, idx, base), want, rel = 1e-9, abs = 1e-11)
  ps <- as.vector(predictSurface(fit, grid.list = list(x = gx, y = gy))$z)
  for (j in seq_len(nq)) {
    ok <- !is.na(ps[j]); add(15, j - 1, as.numeric(ok))
    if (ok) add(8, j - 1, ps[j])
  }
}
D <- mk(22, 2); lam <- 10^runif(1, -2, 0)
surf(0, 2, lam, 0, 0, D$x, D$y, Tps(D$x, D$y, m = 2, lambda = lam, GCV = TRUE))
D <- mk(24, 2); lam <- 10^runif(1, -2, 0); th <- runif(1, 1, 5)
surf(1, 2, lam, th, 1.5, D$x, D$y, Krig(D$x, D$y, Covariance = "Matern", theta = th, smoothness = 1.5, lambda = lam, GCV = TRUE))
data(ozone2)
ok <- which(!is.na(ozone2$y[16, ])); pick <- ok[seq(1, length(ok), by = 3)]
xo <- ozone2$lon.lat[pick, ]; yo <- ozone2$y[16, pick]
surf(0, 2, 0, 0, 0, xo, yo, Tps(xo, yo, m = 2), 1)
emit("fieldskrig", "fields", list(cases))
