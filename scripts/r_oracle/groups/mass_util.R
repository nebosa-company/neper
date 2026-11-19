# MASS Null, area and lm.gls.
#   "null" (n, p, mode 0 position-weighted sum of Null(M) 1 its column count, M[n p] col-major)
#   "area" (id 0 sin 1 x^2 2 exp(-x^2) 3 1/(1+x^2) 4 sqrt 5 |x-0.3| 6 exp(x) cos(3x), a, b, limit, eps)
#   "gls"  (n, p, inverse, mode 0 coef 1 fitted 2 resid 3 rank (position-weighted sums), W[n n], X[n p] col-major (no intercept column added), y[n])
suppressMessages(library(MASS))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-10) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
wsum <- function(v) sum(seq_along(v) * as.numeric(v))
set.seed(20262901)
for (rep in 1:40) {
  n <- sample(2:9, 1); p <- sample(1:min(n, 6), 1); M <- matrix(rnorm(n * p), n, p)
  if (rep %% 4 == 0 && p > 1) M[, p] <- M[, 1] * 2 - M[, p - 1] * 0.5     # rank deficient
  if (rep %% 11 == 0) M[] <- 0
  N <- Null(M)
  add("null", c(n, p, 0, M), wsum(N), 1e-10, 1e-11); add("null", c(n, p, 1, M), ncol(N), 0, 0)
}
fs <- list(sin, function(x) x^2, function(x) exp(-x^2), function(x) 1 / (1 + x^2), sqrt, function(x) abs(x - 0.3), function(x) exp(x) * cos(3 * x))
for (rep in 1:70) {
  id <- (rep - 1) %% 7; a <- if (id == 4) runif(1, 0, 1) else runif(1, -2, 1); b <- a + runif(1, 0.3, 4)
  lim <- sample(c(10, 10, 3, 6, 14), 1); eps <- 10^-sample(2:8, 1)
  v <- suppressWarnings(area(fs[[id + 1]], a, b, limit = lim, eps = eps))
  add("area", c(id, a, b, lim, eps), v, 1e-12, 1e-14)
}
for (rep in 1:30) {
  n <- sample(5:14, 1); p <- sample(1:3, 1); X <- matrix(rnorm(n * p), n, p); y <- as.vector(X %*% rnorm(p)) + rnorm(n)
  B <- matrix(rnorm(n * n), n, n); W <- crossprod(B) / n + diag(runif(n, 0.3, 1.5)); inv <- rep %% 2 == 0
  d <- data.frame(y = y, X)
  f <- lm.gls(y ~ . - 1, data = d, W = W, inverse = inv)
  a <- c(n, p, as.numeric(inv)); tail <- c(W, X, y)
  add("gls", c(a, 0, tail), wsum(f$coefficients), 1e-8, 1e-9); add("gls", c(a, 1, tail), wsum(f$fitted.values), 1e-8, 1e-9)
  add("gls", c(a, 2, tail), wsum(f$residuals), 1e-8, 1e-9); add("gls", c(a, 3, tail), f$rank, 0, 0)
}
emit("mass_util", "MASS", list(cases))
