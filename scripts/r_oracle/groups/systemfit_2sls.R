# systemfit method = "2SLS" (equation by equation). Args: (n, k, q, x[n * k] row-major with the constant first, z[n * q] row-major, y[n], which): which 0 .. k - 1 coefficient, k .. 2k - 1 standard error, 2k sigma^2
suppressMessages(library(systemfit))
cases <- list()
set.seed(20262460)
for (rep in 1:40) {
  n <- sample(30:120, 1); k <- sample(2:4, 1); q <- k + sample(1:3, 1)
  Z <- matrix(rnorm(n * (q - 1)), n, q - 1); X <- matrix(0, n, k - 1)
  for (j in 1:(k - 1)) X[, j] <- Z %*% rnorm(q - 1, 0, 0.6) + rnorm(n)
  y <- 1 + X %*% runif(k - 1, -2, 2) + rnorm(n)
  d <- data.frame(y = as.vector(y), X); names(d)[-1] <- paste0("x", 1:(k - 1)); zz <- data.frame(Z); names(zz) <- paste0("z", 1:(q - 1))
  d <- cbind(d, zz)
  f <- as.formula(paste("y ~", paste(paste0("x", 1:(k - 1)), collapse = " + "))); fi <- as.formula(paste("~", paste(paste0("z", 1:(q - 1)), collapse = " + ")))
  r <- tryCatch(systemfit(list(eq = f), method = "2SLS", inst = fi, data = d), error = function(e) NULL)
  if (is.null(r)) next
  a <- c(n, k, q, as.vector(t(cbind(1, X))), as.vector(t(cbind(1, Z))), as.vector(y))
  cf <- as.numeric(coef(r)); sev <- sqrt(diag(vcov(r))); s2 <- as.numeric(r$residCov)
  for (j in 1:k) { cases[[length(cases) + 1]] <- case("sls", c(a, j - 1), cf[j], rel = 1e-9, abs = 1e-11); cases[[length(cases) + 1]] <- case("sls", c(a, k + j - 1), sev[j], rel = 1e-9, abs = 1e-11) }
  cases[[length(cases) + 1]] <- case("sls", c(a, 2 * k), s2, rel = 1e-9, abs = 1e-11)
}
# 3SLS: "s3" (n, m, q, ks[m], X_1 .. X_m row-major, Z[n * q] row-major, y_1 .. y_m, which 0 .. sum(ks) - 1 coefficient, sum(ks) .. 2 sum(ks) - 1 standard error)
for (rep in 1:30) {
  n <- sample(40:120, 1); m <- sample(2:3, 1); q <- 4 + sample(0:2, 1)
  Z <- matrix(rnorm(n * (q - 1)), n, q - 1); ks <- sample(2:3, m, TRUE)
  d <- data.frame(Z); names(d) <- paste0("z", 1:(q - 1)); Xl <- list(); fl <- list(); common <- rnorm(n)
  for (e in 1:m) {
    xe <- matrix(0, n, ks[e] - 1); for (j in seq_len(ks[e] - 1)) xe[, j] <- Z %*% rnorm(q - 1, 0, 0.6) + rnorm(n)
    d[[paste0("y", e)]] <- as.vector(1 + xe %*% runif(ks[e] - 1, -2, 2) + rnorm(n) + 0.5 * common)
    for (j in seq_len(ks[e] - 1)) d[[paste0("x", e, "_", j)]] <- xe[, j]
    fl[[paste0("e", e)]] <- as.formula(paste0("y", e, " ~ ", paste(paste0("x", e, "_", seq_len(ks[e] - 1)), collapse = " + ")))
    Xl[[e]] <- cbind(1, xe)
  }
  fi <- as.formula(paste("~", paste(paste0("z", 1:(q - 1)), collapse = " + ")))
  r <- tryCatch(suppressWarnings(systemfit(fl, method = "3SLS", inst = fi, data = d)), error = function(e) NULL)
  if (is.null(r)) next
  cf <- as.numeric(coef(r)); sev <- sqrt(diag(vcov(r))); kt <- sum(ks)
  a <- c(n, m, q, ks, unlist(lapply(Xl, function(M) as.vector(t(M)))), as.vector(t(cbind(1, Z))), unlist(lapply(1:m, function(e) d[[paste0("y", e)]])))
  for (j in 1:kt) { cases[[length(cases) + 1]] <- case("s3", c(a, j - 1), cf[j], rel = 1e-7, abs = 1e-9); cases[[length(cases) + 1]] <- case("s3", c(a, kt + j - 1), sev[j], rel = 1e-7, abs = 1e-9) }
}
# OLS and WLS of a two-equation system, answered per equation by twosls with the instruments set to the regressors (WLS only rescales each equation by its residual variance, so the coefficients are OLS and the covariance is the OLS one): "ols" args (n, k, 0, x[n * k], x[n * k] again as the instruments, y[n], which)
for (rep in 1:30) {
  n <- sample(30:120, 1); k <- sample(2:4, 1)
  X <- cbind(1, matrix(rnorm(n * (k - 1)), n, k - 1)); y <- as.vector(X %*% runif(k, -2, 2) + rnorm(n, 0, 1 + rep %% 3))
  X2 <- cbind(1, rnorm(n)); y2 <- as.vector(X2 %*% c(1, 2) + rnorm(n))
  d <- data.frame(y = y, X[, -1, drop = FALSE]); names(d)[-1] <- paste0("x", 1:(k - 1)); d$y2 <- y2; d$w <- X2[, 2]
  f1 <- as.formula(paste("y ~", paste(paste0("x", 1:(k - 1)), collapse = " + ")))
  r <- tryCatch(systemfit(list(a = f1, b = y2 ~ w), method = c("OLS", "WLS")[rep %% 2 + 1], data = d), error = function(e) NULL)
  if (is.null(r)) next
  cf <- as.numeric(coef(r))[1:k]; sev <- sqrt(diag(vcov(r)))[1:k]
  a <- c(n, k, k, as.vector(t(X)), as.vector(t(X)), y)
  for (j in 1:k) { cases[[length(cases) + 1]] <- case("sls", c(a, j - 1), cf[j], rel = 1e-9, abs = 1e-11); cases[[length(cases) + 1]] <- case("sls", c(a, k + j - 1), sev[j], rel = 1e-9, abs = 1e-11) }
}
# W2SLS of a two-equation system (equal to 2SLS equation by equation): the first equation, same layout as "sls"
for (rep in 1:20) {
  n <- sample(30:120, 1); k <- sample(2:4, 1); q <- k + sample(1:3, 1)
  Z <- matrix(rnorm(n * (q - 1)), n, q - 1); X <- matrix(0, n, k - 1)
  for (j in 1:(k - 1)) X[, j] <- Z %*% rnorm(q - 1, 0, 0.6) + rnorm(n)
  y <- 1 + X %*% runif(k - 1, -2, 2) + rnorm(n, 0, 1 + rep %% 3); y2 <- 1 + X[, 1] + 2 * rnorm(n)
  d <- data.frame(y = as.vector(y), y2 = y2, X); names(d)[-(1:2)] <- paste0("x", 1:(k - 1)); zz <- data.frame(Z); names(zz) <- paste0("z", 1:(q - 1)); d <- cbind(d, zz)
  f <- as.formula(paste("y ~", paste(paste0("x", 1:(k - 1)), collapse = " + "))); fi <- as.formula(paste("~", paste(paste0("z", 1:(q - 1)), collapse = " + ")))
  r <- tryCatch(systemfit(list(a = f, b = y2 ~ x1), method = "W2SLS", inst = fi, data = d), error = function(e) NULL)
  if (is.null(r)) next
  cf <- as.numeric(coef(r))[1:k]; sev <- sqrt(diag(vcov(r)))[1:k]
  a <- c(n, k, q, as.vector(t(cbind(1, X))), as.vector(t(cbind(1, Z))), as.vector(y))
  for (j in 1:k) { cases[[length(cases) + 1]] <- case("sls", c(a, j - 1), cf[j], rel = 1e-9, abs = 1e-11); cases[[length(cases) + 1]] <- case("sls", c(a, k + j - 1), sev[j], rel = 1e-9, abs = 1e-11) }
}
emit("systemfit_2sls", "systemfit", list(cases))
