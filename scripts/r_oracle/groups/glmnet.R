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
    case("coef", c(n, p, alpha, std, length(lam), lam, vf, y, X, k - 1, j), cf[j + 1, k], rel = 1e-5, abs = 1e-6)
}
emit("glmnet", "glmnet", list(cases))
