# systemfit linearHypothesis (Wald tests). Args: (kt, nr, df2, b[kt], V[kt * kt] row-major, R[nr * kt] row-major, q[nr], which): 0 the statistic, 1 the Chisq p, 2 the F p
suppressMessages({library(systemfit); library(car)})
cases <- list()
set.seed(20262470)
for (rep in 1:40) {
  n <- sample(30:90, 1); M <- 2; ks <- sample(2:4, M, TRUE); rho <- runif(1, 0.2, 0.8)
  e <- matrix(rnorm(n * M), n) %*% chol(matrix(rho, M, M) + diag(1 - rho, M))
  X <- lapply(ks, function(k) cbind(1, matrix(rnorm(n * (k - 1)), n)))
  Y <- sapply(seq_len(M), function(m) as.vector(X[[m]] %*% rnorm(ks[m])) + e[, m])
  d <- list(); eqs <- list()
  for (m in seq_len(M)) { for (j in seq_len(ks[m] - 1)) d[[paste0("x", m, "_", j)]] <- X[[m]][, j + 1]; d[[paste0("y", m)]] <- Y[, m] }
  d <- as.data.frame(d)
  for (m in seq_len(M)) eqs[[paste0("e", m)]] <- as.formula(paste0("y", m, " ~ ", paste(c("1", if (ks[m] > 1) paste0("x", m, "_", seq_len(ks[m] - 1))), collapse = " + ")))
  f <- tryCatch(suppressWarnings(systemfit(eqs, c("SUR", "OLS")[rep %% 2 + 1], data = d)), error = function(e) NULL)
  if (is.null(f)) next
  kt <- sum(ks); nr <- sample(1:2, 1); Rm <- matrix(round(rnorm(nr * kt), 1), nr, kt); q <- round(rnorm(nr), 1)
  hc <- tryCatch(linearHypothesis(f, Rm, q, test = "Chisq"), error = function(e) NULL); hf <- tryCatch(linearHypothesis(f, Rm, q, test = "F"), error = function(e) NULL)
  if (is.null(hc) || is.null(hf)) next
  a <- c(kt, nr, f$df.residual, as.numeric(coef(f)), as.vector(t(vcov(f))), as.vector(t(Rm)), q)
  cases[[length(cases) + 1]] <- case("wald", c(a, 0), hc[2, "Chisq"], rel = 1e-5, abs = 1e-9)
  cases[[length(cases) + 1]] <- case("wald", c(a, 1), hc[2, "Pr(>Chisq)"], rel = 1e-3, abs = 1e-6)
  cases[[length(cases) + 1]] <- case("wald", c(a, 2), hf[2, "Pr(>F)"], rel = 1e-3, abs = 1e-6)
}
emit("systemfit_wald", "systemfit", list(cases))
