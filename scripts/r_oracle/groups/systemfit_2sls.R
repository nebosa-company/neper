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
emit("systemfit_2sls", "systemfit", list(cases))
