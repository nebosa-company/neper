# glmnet gaussian family at a user lambda sequence (thresh 1e-14 so glmnet is converged too).
#   args: (n, p, alpha, standardize, nl, lambda[nl], vf[p], y[n], X[n*p] column-major, k, j)  coefficient j (0 intercept) at lambda k
suppressMessages(library(glmnet))
cases <- list()
set.seed(20261116)
for (rep in 1:12) {
  n <- sample(30:80, 1); p <- sample(3:7, 1)
  X <- matrix(round(rnorm(n * p) * runif(p, 0.5, 3), 3), n, p)
  y <- round(drop(X %*% c(2, -1, 0, 0.5, rep(0, 3))[1:p]) + rnorm(n), 3)
  alpha <- c(1, 0.5, 0.2, 0, 0.9)[(rep %% 5) + 1]; std <- rep %% 3 != 0
  vf <- if (rep %% 4 == 0) round(runif(p, 0.3, 2), 2) else rep(1, p)
  xs <- scale(X, scale = FALSE); lmax <- max(abs(crossprod(xs, y - mean(y)))) / n / max(alpha, 1e-3)
  lam <- exp(seq(log(lmax), log(lmax * 0.01), length.out = 8))
  f <- glmnet(X, y, alpha = alpha, standardize = std, penalty.factor = vf, lambda = lam, thresh = 1e-14)
  cf <- as.matrix(coef(f))
  for (k in c(1, 3, 6, 8)) for (j in 0:p) cases[[length(cases) + 1]] <-
    case("coef", c(n, p, alpha, std, length(lam), lam, vf, y, X, k - 1, j, 0, 0, 0), cf[j + 1, k], rel = 1e-5, abs = 1e-6)
}
# observation weights: the same layout with the flag 1 and the n weights after it
for (rep in 1:12) {
  n <- sample(30:70, 1); p <- sample(3:6, 1); X <- matrix(round(rnorm(n * p), 3), n, p); y <- round(X[, 1] * 2 + rnorm(n), 3)
  w <- round(runif(n, 0.2, 3), 2); alpha <- c(1, 0.5, 0.2, 0.9)[(rep %% 4) + 1]; std <- rep %% 3 != 0; vf <- rep(1, p)
  wn <- w / sum(w); mx <- colSums(wn * X); sx <- if (std) sqrt(colSums(wn * (X - rep(mx, each = n))^2)) else rep(1, p)
  lmax <- max(abs(colSums(wn * (X - rep(mx, each = n)) * (y - sum(wn * y))) / sx)) / max(alpha, 1e-3)
  lam <- exp(seq(log(lmax), log(lmax * 0.01), length.out = 8))
  f <- glmnet(X, y, weights = w, alpha = alpha, standardize = std, lambda = lam, thresh = 1e-14)
  cf <- as.matrix(coef(f))
  for (k in c(1, 4, 8)) for (j in 0:p) cases[[length(cases) + 1]] <-
    case("coef", c(n, p, alpha, std, length(lam), lam, vf, y, X, k - 1, j, 1, 0, 0, w), cf[j + 1, k], rel = 1e-5, abs = 1e-6)
}
# offsets: glmnet(offset = o) equals the fit of y - o (the caller subtracts it)
for (rep in 1:8) {
  n <- sample(30:70, 1); p <- sample(3:6, 1); X <- matrix(round(rnorm(n * p), 3), n, p); y <- round(X[, 1] * 2 + rnorm(n), 3); o <- round(rnorm(n), 2)
  alpha <- c(1, 0.5, 0.2)[(rep %% 3) + 1]; ye <- y - o
  lmax <- max(abs(crossprod(scale(X, scale = FALSE), ye - mean(ye)))) / n / max(alpha, 1e-3)
  lam <- exp(seq(log(lmax), log(lmax * 0.01), length.out = 8))
  f <- suppressWarnings(glmnet(X, y, offset = o, alpha = alpha, standardize = TRUE, lambda = lam, thresh = 1e-14)); cf <- as.matrix(coef(f))
  for (k in c(2, 5, 8)) for (j in 0:p) cases[[length(cases) + 1]] <-
    case("coef", c(n, p, alpha, 1, length(lam), lam, rep(1, p), ye, X, k - 1, j, 0, 0, 0), cf[j + 1, k], rel = 1e-5, abs = 1e-6)
}
# box constraints: the same layout with the bounds flag 1, lower[p] and upper[p] after it (standardize on)
for (rep in 1:12) {
  n <- sample(30:70, 1); p <- sample(3:6, 1); X <- matrix(round(rnorm(n * p), 3), n, p); y <- round(X[, 1] * 2 - X[, 2] + rnorm(n), 3)
  alpha <- c(1, 0.5, 0.2, 0.9)[(rep %% 4) + 1]; std <- rep %% 3 != 0
  lo <- round(-runif(p, 0, 1.5), 2); up <- round(runif(p, 0, 1.5), 2); if (rep %% 2 == 0) lo[1] <- 0
  lmax <- max(abs(crossprod(scale(X, scale = FALSE), y - mean(y)))) / n / max(alpha, 1e-3)
  lam <- exp(seq(log(lmax), log(lmax * 0.01), length.out = 8))
  f <- suppressWarnings(glmnet(X, y, alpha = alpha, standardize = std, lambda = lam, lower.limits = lo, upper.limits = up, thresh = 1e-14)); cf <- as.matrix(coef(f))
  for (k in c(2, 5, 8)) for (j in 0:p) cases[[length(cases) + 1]] <-
    case("coef", c(n, p, alpha, std, length(lam), lam, rep(1, p), y, X, k - 1, j, 0, 1, 0, lo, up), cf[j + 1, k], rel = 1e-5, abs = 1e-6)
}
# binomial "bin": the "coef" layout with y in {0, 1}; the trailing flags are ignored
for (rep in 1:12) {
  n <- sample(60:120, 1); p <- sample(3:6, 1); X <- matrix(round(rnorm(n * p), 3), n, p); y <- rbinom(n, 1, plogis(X[, 1] - 0.5 * X[, 2]))
  alpha <- c(1, 0.5, 0.2, 0.9)[(rep %% 4) + 1]; std <- rep %% 3 != 0; vf <- if (rep %% 4 == 0) round(runif(p, 0.3, 2), 2) else rep(1, p)
  xs <- if (std) scale(X) * sqrt(n / (n - 1)) else scale(X, scale = FALSE)
  lmax <- max(abs(crossprod(xs, y - mean(y)) / vf)) / n / max(alpha, 1e-3) * (sum(vf) / p)
  lam <- exp(seq(log(lmax), log(lmax * 0.05), length.out = 8))
  f <- suppressWarnings(glmnet(X, y, family = "binomial", alpha = alpha, standardize = std, penalty.factor = vf, lambda = lam, thresh = 1e-14)); cf <- as.matrix(coef(f))
  for (k in c(2, 5, 8)) for (j in 0:p) cases[[length(cases) + 1]] <-
    case("bin", c(n, p, alpha, std, length(lam), lam, vf, y, X, k - 1, j, 0, 0, 0), cf[j + 1, k], rel = 1e-5, abs = 1e-6)
}
# poisson "pois": the "coef" layout with y a count
for (rep in 1:12) {
  n <- sample(60:120, 1); p <- sample(3:6, 1); X <- matrix(round(rnorm(n * p), 3), n, p); y <- rpois(n, exp(0.5 + 0.4 * X[, 1] - 0.3 * X[, 2]))
  alpha <- c(1, 0.5, 0.2, 0.9)[(rep %% 4) + 1]; std <- rep %% 3 != 0; vf <- if (rep %% 4 == 0) round(runif(p, 0.3, 2), 2) else rep(1, p)
  xs <- if (std) scale(X) * sqrt(n / (n - 1)) else scale(X, scale = FALSE)
  lmax <- max(abs(crossprod(xs, y - mean(y)) / vf)) / n / max(alpha, 1e-3) * (sum(vf) / p)
  lam <- exp(seq(log(lmax), log(lmax * 0.05), length.out = 8))
  f <- suppressWarnings(glmnet(X, y, family = "poisson", alpha = alpha, standardize = std, penalty.factor = vf, lambda = lam, thresh = 1e-14)); cf <- as.matrix(coef(f))
  for (k in c(2, 5, 8)) for (j in 0:p) cases[[length(cases) + 1]] <-
    case("pois", c(n, p, alpha, std, length(lam), lam, vf, y, X, k - 1, j, 0, 0, 0), cf[j + 1, k], rel = 1e-5, abs = 1e-6)
}
# weights and offsets for the glm families: "bin" / "pois" with flags (1, 0, 1) then w[n], offset[n]
for (fam in c("binomial", "poisson")) for (rep in 1:8) {
  n <- sample(60:110, 1); p <- sample(3:5, 1); X <- matrix(round(rnorm(n * p), 3), n, p); o <- round(rnorm(n, 0, 0.3), 2); w <- round(runif(n, 0.3, 3), 2)
  y <- if (fam == "binomial") rbinom(n, 1, plogis(X[, 1] + o)) else rpois(n, exp(0.4 + 0.4 * X[, 1] + o))
  alpha <- c(1, 0.5, 0.9, 0.2)[(rep %% 4) + 1]; std <- rep %% 3 != 0
  wn <- w / sum(w); mx <- colSums(wn * X); sx <- if (std) sqrt(colSums(wn * (X - rep(mx, each = n))^2)) else rep(1, p)
  lmax <- max(abs(colSums(wn * (X - rep(mx, each = n)) * (y - sum(wn * y))) / sx)) / max(alpha, 1e-3)
  lam <- exp(seq(log(lmax), log(lmax * 0.1), length.out = 6))
  f <- suppressWarnings(glmnet(X, y, family = fam, weights = w, offset = o, alpha = alpha, standardize = std, lambda = lam, thresh = 1e-14)); cf <- as.matrix(coef(f))
  for (k in c(2, 4, 6)) for (j in 0:p) cases[[length(cases) + 1]] <-
    case(if (fam == "binomial") "bin" else "pois", c(n, p, alpha, std, length(lam), lam, rep(1, p), y, X, k - 1, j, 1, 0, 1, w, o), cf[j + 1, k], rel = 1e-5, abs = 1e-6)
}
# the automatic lambda sequence: "lpath" (n, p, alpha, std, k, vf[p], y[n], X[n p]) the k-th lambda (0-based) of glmnet(...)$lambda
for (rep in 1:20) {
  n <- sample(30:80, 1); p <- sample(3:8, 1); X <- matrix(rnorm(n * p), n); y <- X[, 1] * 2 + rnorm(n); al <- sample(c(0.2, 0.5, 0.7, 1), 1); std <- rep %% 2; vf <- if (rep %% 3 == 0) runif(p, 0.5, 2) else rep(1, p)
  f <- glmnet(X, y, alpha = al, standardize = as.logical(std), penalty.factor = vf); for (k in c(0, 1, 5, 10, min(length(f$lambda) - 1, 20))) cases[[length(cases) + 1]] <- case("lpath", c(n, p, al, std, k, vf, y, X), f$lambda[k + 1], rel = 1e-9, abs = 1e-12)
}
emit("glmnet", "glmnet", list(cases))
