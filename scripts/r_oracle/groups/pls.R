# pls: kernelpls, simpls, oscorespls and widekernelpls fits.
#   args: (method 0 kernelpls 1 simpls 2 oscorespls 3 widekernelpls, n, p, q, ncomp, center, X row-major, Y row-major, a, what)
#   fn "coef": the sum / position-weighted sum / sum of squares of the coefficient matrix at a components (what 0 1 2, position by row-major p by q)
#   fn "fit": the same sums of the fitted values at a components; fn "tt": sum of squares of the scores column a (sign free), "pp": of the loadings column a;
#   fn "xvar": the explained X variance of component a; with one response the signed sums of scores and loadings ("ttsum", "ppsum")
suppressMessages(library(pls))
cases <- list()
add <- function(fn, args, want, rel = 1e-8) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-10)
set.seed(20261122)
flat <- function(m) as.vector(t(m))
sums <- function(fn, a, v) { v <- as.numeric(v); w <- seq_along(v); add(fn, c(a, 0), sum(v)); add(fn, c(a, 1), sum(w * v)); add(fn, c(a, 2), sum(v^2)) }
methods <- c("kernelpls", "simpls", "oscorespls", "widekernelpls")
for (rep in 1:8) {
  n <- c(30, 40, 25, 50)[(rep - 1) %% 4 + 1]; p <- c(6, 8, 12, 5)[(rep - 1) %% 4 + 1]; q <- c(1, 1, 2, 3)[(rep - 1) %% 4 + 1]
  Z <- matrix(rnorm(n * 3), n, 3); X <- Z %*% matrix(rnorm(3 * p), 3, p) + matrix(rnorm(n * p, 0, 0.3), n, p)
  Y <- Z %*% matrix(rnorm(3 * q), 3, q) + matrix(rnorm(n * q, 0, 0.3), n, q)
  ncomp <- min(4, p)
  for (m in 0:3) for (center in c(TRUE, FALSE)) {
    fit <- tryCatch(suppressWarnings(plsr(Y ~ X, ncomp = ncomp, method = methods[m + 1], center = center)), error = function(e) NULL)
    if (is.null(fit)) next
    for (k in seq_len(ncomp)) {
      a <- c(m, n, p, q, ncomp, as.numeric(center), flat(X), flat(Y), k)
      B <- fit$coefficients[, , k]; sums("coef", a, flat(matrix(B, p, q)))
      sums("fit", a, flat(matrix(fit$fitted.values[, , k], n, q)))
      add("tt", a, sum(fit$scores[, k]^2)); add("pp", a, sum(fit$loadings[, k]^2)); add("xvar", a, fit$Xvar[k])
      if (q == 1) { add("ttsum", a, sum(fit$scores[, k] * seq_len(n))); add("ppsum", a, sum(fit$loadings[, k] * seq_len(p))) }
    }
  }
}
# cppls: the same layout with method 5 (coefficients and fitted values only; the signs of its scores and loadings are free)
for (rep in 1:8) {
  n <- c(30, 40, 25, 50)[(rep - 1) %% 4 + 1]; p <- c(6, 8, 12, 5)[(rep - 1) %% 4 + 1]; q <- c(1, 2, 2, 3)[(rep - 1) %% 4 + 1]
  Z <- matrix(rnorm(n * 3), n, 3); X <- Z %*% matrix(rnorm(3 * p), 3, p) + matrix(rnorm(n * p, 0, 0.3), n, p)
  Y <- Z %*% matrix(rnorm(3 * q), 3, q) + matrix(rnorm(n * q, 0, 0.3), n, q)
  ncomp <- min(4, p)
  for (center in c(TRUE, FALSE)) {
    fit <- tryCatch(suppressWarnings(cppls(Y ~ X, ncomp = ncomp, center = center)), error = function(e) NULL)
    if (is.null(fit)) next
    for (k in seq_len(ncomp)) {
      a <- c(5, n, p, q, ncomp, as.numeric(center), flat(X), flat(Y), k)
      B <- fit$coefficients[, , k]; sums("coef", a, flat(matrix(B, p, q)))
      sums("fit", a, flat(matrix(fit$fitted.values[, , k], n, q)))
      add("tt", a, sum(fit$scores[, k]^2)); add("pp", a, sum(fit$loadings[, k]^2)); add("xvar", a, fit$Xvar[k])
    }
  }
}
# cppls with Y.add (fn "coef"/"fit" sums, method 6 = cppls with qa extra response columns): args (6, n, p, q, ncomp, center, X, Y, qa, Ya, k)
for (rep in 1:8) {
  n <- c(30, 40, 25, 50)[(rep - 1) %% 4 + 1]; p <- c(6, 8, 12, 5)[(rep - 1) %% 4 + 1]; q <- c(1, 2, 2, 3)[(rep - 1) %% 4 + 1]; qa <- sample(1:2, 1)
  Z <- matrix(rnorm(n * 3), n, 3); X <- Z %*% matrix(rnorm(3 * p), 3, p) + matrix(rnorm(n * p, 0, 0.3), n, p)
  Y <- Z %*% matrix(rnorm(3 * q), 3, q) + matrix(rnorm(n * q, 0, 0.3), n, q); Ya <- Z %*% matrix(rnorm(3 * qa), 3, qa) + matrix(rnorm(n * qa, 0, 0.3), n, qa)
  ncomp <- min(4, p)
  for (center in c(TRUE, FALSE)) {
    fit <- tryCatch(suppressWarnings(cppls.fit(X, Y, ncomp = ncomp, Y.add = Ya, center = center)), error = function(e) NULL)
    if (is.null(fit)) next
    for (k in seq_len(ncomp)) {
      a <- c(6, n, p, q, ncomp, as.numeric(center), flat(X), flat(Y), qa, flat(Ya), k)
      sums("coef", a, flat(matrix(fit$coefficients[, , k], p, q))); sums("fit", a, flat(matrix(fit$fitted.values[, , k], n, q)))
    }
  }
}
# cppls with the power search (method 7): args (7, n, p, q, ncomp, center, X, Y, lower, upper, k, what); fn "coef" "fit"
for (rep in 1:8) {
  n <- c(30, 40, 25, 50)[(rep - 1) %% 4 + 1]; p <- c(6, 8, 12, 5)[(rep - 1) %% 4 + 1]; q <- c(1, 2, 2, 3)[(rep - 1) %% 4 + 1]
  Z <- matrix(rnorm(n * 3), n, 3); X <- Z %*% matrix(rnorm(3 * p), 3, p) + matrix(rnorm(n * p, 0, 0.3), n, p)
  Y <- Z %*% matrix(rnorm(3 * q), 3, q) + matrix(rnorm(n * q, 0, 0.3), n, q)
  ncomp <- min(3, p)
  for (lu in list(c(0.2, 0.8), c(0.3, 0.3), c(0, 1), c(0.1, 0.9))) {
    center <- rep %% 2 == 0
    fit <- tryCatch(suppressWarnings(cppls.fit(X, Y, ncomp = ncomp, center = center, lower = lu[1], upper = lu[2])), error = function(e) NULL)
    if (is.null(fit)) next
    for (k in seq_len(ncomp)) {
      a <- c(7, n, p, q, ncomp, as.numeric(center), flat(X), flat(Y), lu[1], lu[2], k)
      sums("coef", a, flat(matrix(fit$coefficients[, , k], p, q))); sums("fit", a, flat(matrix(fit$fitted.values[, , k], n, q)))
    }
  }
}
#   method 4 is pcr (svdpc); cross-validation with the segments passed explicitly: fn "press" "adj" (args (m, n, p, q, ncomp, center, X, Y, nseg, segid[n], j, ac)), "press0" (j),
#   "msep" and "r2" with (..., est 0 train 1 CV 2 adjCV (msep only), j, ac) where ac 0 is the intercept-only model
for (rep in 1:8) {
  n <- c(30, 40, 25, 50)[(rep - 1) %% 4 + 1]; p <- c(6, 8, 12, 5)[(rep - 1) %% 4 + 1]; q <- c(1, 1, 2, 3)[(rep - 1) %% 4 + 1]
  Z <- matrix(rnorm(n * 3), n, 3); X <- Z %*% matrix(rnorm(3 * p), 3, p) + matrix(rnorm(n * p, 0, 0.3), n, p)
  Y <- Z %*% matrix(rnorm(3 * q), 3, q) + matrix(rnorm(n * q, 0, 0.3), n, q)
  ncomp <- min(4, p)
  fitm <- function(m, ...) if (m == 4) pcr(Y ~ X, ...) else if (m == 5) cppls(Y ~ X, ...) else plsr(Y ~ X, method = methods[m + 1], ...)
  for (center in c(TRUE, FALSE)) {
    fit <- fitm(4, ncomp = ncomp, center = center)
    for (k in seq_len(ncomp)) {
      a <- c(4, n, p, q, ncomp, as.numeric(center), flat(X), flat(Y), k)
      sums("coef", a, flat(matrix(fit$coefficients[, , k], p, q))); sums("fit", a, flat(matrix(fit$fitted.values[, , k], n, q)))
      add("tt", a, sum(fit$scores[, k]^2)); add("pp", a, sum(fit$loadings[, k]^2)); add("xvar", a, fit$Xvar[k])
    }
  }
  segs <- cvsegments(n, 5, type = "random"); segid <- integer(n); for (s in seq_along(segs)) segid[segs[[s]]] <- s - 1
  for (m in c(0, 1, 2, 4, 5)) {
    fitj <- tryCatch(suppressWarnings(fitm(m, ncomp = ncomp, validation = "CV", segments = segs, jackknife = TRUE)), error = function(e) NULL)
    if (is.null(fitj)) next
    for (k in unique(c(2, ncomp))) {
      jt <- jack.test(fitj, ncomp = k); a <- c(m, n, p, q, ncomp, 1, flat(X), flat(Y), length(segs), segid, k)
      sums("jsd", a, flat(matrix(jt$sd, p, q))); sums("jt", a, flat(matrix(jt$tvalues, p, q)))
    }
  }
  for (m in c(0, 1, 2, 4, 5)) {
    fit <- tryCatch(suppressWarnings(fitm(m, ncomp = ncomp, validation = "CV", segments = segs)), error = function(e) NULL)
    if (is.null(fit)) next
    nc <- fit$validation$ncomp
    b <- c(m, n, p, q, ncomp, 1, flat(X), flat(Y), length(segs), segid)
    for (j in seq_len(q)) {
      add("press0", c(b, j - 1, 0), fit$validation$PRESS0[j])
      for (k in seq_len(nc)) { add("press", c(b, j - 1, k - 1), fit$validation$PRESS[j, k]); add("adj", c(b, j - 1, k - 1), fit$validation$adj[j, k]) }
    }
    ms <- MSEP(fit, estimate = c("train", "CV", "adjCV"), intercept = TRUE)$val; r2 <- R2(fit, estimate = c("train", "CV"), intercept = TRUE)$val
    for (j in seq_len(q)) for (k in 0:nc) {
      for (est in 0:2) add("msep", c(b, est, j - 1, k), ms[est + 1, j, k + 1])
      for (est in 0:1) add("r2", c(b, est, j - 1, k), r2[est + 1, j, k + 1])
    }
  }
}
emit("pls", "pls", list(cases))
