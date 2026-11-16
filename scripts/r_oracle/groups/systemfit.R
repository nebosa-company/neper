# systemfit SUR, equations with their own regressors on the same observations.
#   args: (n, M, passes, df_cor, k_1 .. k_M, y_1[n] .. y_M[n], then each equation's x (n by k_m, row-major, constant first))
#   fn "coef" "se" (weighted by position over all coefficients), "sig" (residual covariance, weighted by position)
suppressMessages(library(systemfit))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-7, abs = 1e-9)
ws <- function(v) sum(v * seq_along(v))
set.seed(20261215)
for (rep in 1:24) {
  n <- sample(25:80, 1); M <- sample(2:3, 1); passes <- sample(1:3, 1); dfc <- rep %% 2
  ks <- sample(2:4, M, TRUE); rho <- runif(1, 0.2, 0.8)
  e <- matrix(rnorm(n * M), n) %*% chol(matrix(rho, M, M) + diag(1 - rho, M))
  X <- lapply(ks, function(k) cbind(1, matrix(rnorm(n * (k - 1)), n)))
  Y <- sapply(seq_len(M), function(m) as.vector(X[[m]] %*% rnorm(ks[m])) + e[, m])
  d <- list(); eqs <- list()
  for (m in seq_len(M)) { for (j in seq_len(ks[m] - 1)) d[[paste0("x", m, "_", j)]] <- X[[m]][, j + 1]; d[[paste0("y", m)]] <- Y[, m] }
  d <- as.data.frame(d)
  for (m in seq_len(M)) eqs[[paste0("e", m)]] <- as.formula(paste0("y", m, " ~ ", paste(c("1", if (ks[m] > 1) paste0("x", m, "_", seq_len(ks[m] - 1))), collapse = " + ")))
  f <- tryCatch(suppressWarnings(systemfit(eqs, "SUR", data = d, control = systemfit.control(methodResidCov = if (dfc) "geomean" else "noDfCor", maxiter = passes, tol = 1e-300))), error = function(e) { message(conditionMessage(e)); NULL })
  if (is.null(f)) next
  a <- c(n, M, passes, dfc, ks, as.vector(Y), unlist(lapply(X, function(x) as.vector(t(x)))))
  s <- summary(f)$coefficients
  add("coef", a, ws(coef(f))); add("se", a, ws(s[, 2])); add("sig", a, ws(as.vector(t(f$residCov))))
}
emit("systemfit", "systemfit", list(cases))
