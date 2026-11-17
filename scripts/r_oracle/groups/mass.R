# MASS: mad, huber, hubers, fitdistr (normal, exponential, poisson, geometric, log-normal), boxcox log-likelihood, bandwidth.nrd.
#   args: (n, x..., p1, p2)   fn "mad" "bw" (no extra); "huber_mu" "huber_s" "hubers_mu" "hubers_s" (p1 = k); "fd" (p1 = family 0..4, p2 = quantity 0 est1 1 est2 2 se1 3 se2 4 loglik)
#   "boxcox": (n, y..., x1..., lambda): the log-likelihood with a design of an intercept and one covariate
suppressMessages(library(MASS))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-10)
set.seed(20261115)
for (rep in 1:10) {
  n <- sample(10:40, 1); x <- round(c(rnorm(n - 2, 5, 2), 20, -9) + 0, 3); x2 <- round(rexp(n, 0.4) + 0.1, 3)
  add("mad", c(n, x, 0, 0), mad(x)); add("bw", c(n, x, 0, 0), bandwidth.nrd(x))
  for (k in c(1, 1.5, 2)) {
    add("huber_mu", c(n, x, k, 0), huber(x, k)$mu); add("huber_s", c(n, x, k, 0), huber(x, k)$s)
    h <- hubers(x, k); add("hubers_mu", c(n, x, k, 0), h$mu); add("hubers_s", c(n, x, k, 0), h$s)
  }
  for (fam in 0:4) {
    d <- switch(fam + 1, x, x2, rpois(n, 3), rgeom(n, 0.3), x2)
    f <- suppressWarnings(fitdistr(d, c("normal", "exponential", "poisson", "geometric", "log-normal")[fam + 1]))
    est <- unname(f$estimate); se <- unname(f$sd)
    add("fd", c(n, d, fam, 0), est[1]); add("fd", c(n, d, fam, 2), se[1]); add("fd", c(n, d, fam, 4), f$loglik)
    if (length(est) > 1) { add("fd", c(n, d, fam, 1), est[2]); add("fd", c(n, d, fam, 3), se[2]) }
  }
  y <- round(x2 * 2 + rexp(n), 3); cv <- round(rnorm(n), 3)
  lm0 <- lm(y ~ cv, y = TRUE, qr = TRUE)
  for (lam in c(-1, -0.5, 0, 0.01, 0.3, 1, 2)) add("boxcox", c(n, y, cv, lam), boxcox(lm0, lambda = lam, plotit = FALSE)$y)
}
for (rep in 1:30) {
  m <- sample(2:8, 1); n <- sample(2:8, 1); X <- matrix(round(rnorm(m * n), 3), m, n)
  if (rep %% 3 == 0 && n > 2) X[, n] <- X[, 1] + X[, 2]
  g <- as.vector(ginv(X)); w <- seq_along(g)
  add("ginv_sum", c(m, n, X), sum(g)); add("ginv_w", c(m, n, X), sum(w * g)); add("ginv_len", c(m, n, X), length(g))
}
# rlm(y ~ X, Huber, MAD): "rlm" (n, p, which, y[n], X[n p] column-major with the intercept first) which 0 .. p - 1 coef, p scale, p + 1 iterations, p + 2 converged
for (rep in 1:30) {
  n <- sample(15:60, 1); p <- sample(2:4, 1); X <- cbind(1, matrix(rnorm(n * (p - 1)), n, p - 1)); y <- as.vector(X %*% rnorm(p)) + rnorm(n) + ifelse(runif(n) < 0.1, rnorm(n, 0, 6), 0)
  d <- data.frame(y = y, X[, -1, drop = FALSE]); fit <- rlm(y ~ ., d); st <- c(coef(fit), fit$s, length(fit$conv), as.numeric(fit$converged))
  for (j in seq_along(st)) add("rlm", c(n, p, j - 1, y, X), st[j])
  for (ps in 1:2) { f2 <- tryCatch(suppressWarnings(rlm(y ~ ., d, psi = if (ps == 1) psi.bisquare else psi.hampel)), error = function(e) NULL); if (is.null(f2)) next
    st2 <- c(coef(f2), f2$s, length(f2$conv), as.numeric(f2$converged)); for (j in seq_along(st2)) add("rlm", c(n, p, 100 * ps + j - 1, y, X), st2[j]) }
}
# kde2d: "kde2d" (n, n1, n2, h1, h2 (0 = default), lims[4], index (column-major z cell), x[n], y[n])
for (rep in 1:20) {
  n <- sample(10:40, 1); xx <- rnorm(n); yy <- 0.5 * xx + rnorm(n); n1 <- sample(3:8, 1); n2 <- sample(3:8, 1); lm_ <- c(range(xx) + c(-0.5, 0.5), range(yy) + c(-0.5, 0.5))
  useh <- rep %% 2 == 0; h <- if (useh) c(runif(1, 0.3, 1.5), runif(1, 0.3, 1.5)) else c(0, 0)
  k <- if (useh) kde2d(xx, yy, h = h, n = c(n1, n2), lims = lm_) else kde2d(xx, yy, n = c(n1, n2), lims = lm_)
  for (idx in seq_len(n1 * n2)) add("kde2d", c(n, n1, n2, h, lm_, idx - 1, xx, yy), as.vector(k$z)[idx])
}
emit("mass", "MASS", list(cases))
