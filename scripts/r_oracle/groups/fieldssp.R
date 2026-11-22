# fieldssp: fields spatialProcess (Matern, exponential; lambda and aRange estimated, one of them fixed, or both fixed) and predictSurface's convex hull mask.
#   one "sp" case = args c(op, idx, ctype, nu, flags, lambda0, aRange0, n, d, nq, x row-major, y, xq row-major); op meanings are at the top of lib/e/algo/stat/fieldssp.e
suppressMessages(library(fields)); options(warn = -1)
cases <- list()
set.seed(20262030)
rows <- function(M) as.vector(t(as.matrix(M)))
one <- function(ctype, nu, flags, lam0, ar0, x, y, xq, fit, grid = NULL, rel = 1e-9) {
  x <- as.matrix(x); xq <- as.matrix(xq); n <- nrow(x); d <- ncol(x); nq <- nrow(xq)
  base <- c(ctype, nu, flags, lam0, ar0, n, d, nq, rows(x), y, rows(xq))
  add <- function(op, idx, want, r = rel) cases[[length(cases) + 1]] <<- case("sp", c(op, idx, base), want, rel = r, abs = 1e-11)
  s <- fit$summary
  add(0, 0, s["lambda"]); add(1, 0, s["aRange"]); add(2, 0, s["lnProfileLike.FULL"]); add(3, 0, s["lnProfileREML.FULL"])
  add(4, 0, s["sigma2"]); add(5, 0, s["tau"])
  for (j in seq_len(nrow(as.matrix(fit$d)))) add(6, j - 1, as.matrix(fit$d)[j, 1])
  for (j in c(1, 2, n)) add(7, j - 1, fit$c.coef[j])
  for (j in c(1, 2)) add(8, j - 1, fit$fitted.values[j])
  pr <- predict(fit, xq); se <- predictSE(fit, xq)
  for (j in seq_len(nq)) { add(9, j - 1, pr[j]); add(10, j - 1, se[j]) }
  if (!is.null(grid)) {
    # predictSurface on a grid (x varies fastest): the mask and the interior values
    ps <- predictSurface(fit, grid.list = grid)$z
    for (j in seq_len(nq)) {
      ok <- !is.na(as.vector(ps)[j])
      add(11, j - 1, as.numeric(ok))
      if (ok) add(9, j - 1, as.vector(ps)[j])
    }
  }
}
mk <- function(n, d) {
  x <- matrix(runif(n * d, 0, 10), n, d) * rep(runif(d, 0.5, 2), each = n) + rep(runif(d, -3, 3), each = n)
  y <- sin(x[, 1] / 2) + (if (d > 1) x[, 2] * 0.3 else 0) + rnorm(n, 0, 0.3)
  list(x = x, y = y, xq = x[seq_len(3), , drop = FALSE] + matrix(runif(3 * d, -0.3, 0.3), 3, d))
}
gridq <- function(x) {
  gx <- seq(min(x[, 1]) - 0.3, max(x[, 1]) + 0.3, length.out = 4); gy <- seq(min(x[, 2]) - 0.3, max(x[, 2]) + 0.3, length.out = 4)
  list(grid = list(x = gx, y = gy), xq = as.matrix(expand.grid(gx, gy)))
}
cfg <- list(
  list(1, 1, 3, 25, 2), list(1, 1.5, 3, 30, 2), list(2, 0, 3, 25, 2), list(1, 2, 3, 28, 2), list(1, 1, 3, 30, 1),
  list(1, 1, 2, 26, 2), list(1, 1, 1, 26, 2), list(2, 0, 2, 24, 2), list(2, 0, 1, 24, 2)
)
for (cf in cfg) {
  ctype <- cf[[1]]; nu <- cf[[2]]; flags <- cf[[3]]; n <- cf[[4]]; d <- cf[[5]]
  D <- mk(n, d)
  lam0 <- 10^runif(1, -2, -0.5); dmax <- sqrt(sum(apply(D$x, 2, function(v) diff(range(v)))^2)); ar0 <- runif(1, 0.15, 0.5) * dmax
  ca <- if (ctype == 1) list(Covariance = "Matern", smoothness = nu) else list(Covariance = "Exponential")
  if (flags %% 2 == 0) ca$lambda <- lam0
  if (flags %/% 2 == 0) ca$aRange <- ar0
  fit <- spatialProcess(D$x, D$y, cov.args = ca)
  g <- if (d == 2) gridq(D$x) else NULL
  one(ctype, nu, flags, lam0, ar0, D$x, D$y, if (d == 2) g$xq else D$xq, fit, if (d == 2) g$grid else NULL)
}
emit("fieldssp", "fields", list(cases))
