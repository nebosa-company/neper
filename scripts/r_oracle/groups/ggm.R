# ggm: partial correlations and the Gaussian graph fits.
#   "pcor"  args (p, nu, u[nu] 1-based, S[p*p] row-major)            -> pcor(u, S)
#   "parcor" args (p, S[p*p], i, j)                                   -> parcor(S)[i, j] (0-based)
#   "pctest" args (r, q, n, which 0 tval 1 df 2 pvalue)
#   "dag" / "con" / "cov" args (p, n, S[p*p], A[p*p], q): q 0..p*p-1 Shat row-major; dag then p Dhat, dev, df, p*p Ahat;
#         con and cov then dev, df, it
suppressMessages(library(ggm))
cases <- list()
set.seed(20261116)
rowm <- function(M) as.vector(t(M))
rndS <- function(p, n) { x <- matrix(rnorm(n * p), n, p) %*% chol(crossprod(matrix(rnorm(p * p), p, p)) + diag(p)); S <- crossprod(scale(x, scale = FALSE)) / n; dimnames(S) <- list(letters[1:p], letters[1:p]); S }
for (rep in 1:20) {
  p <- sample(3:6, 1); n <- sample(30:100, 1); S <- rndS(p, n)
  nu <- sample(2:p, 1); u <- sample(p, nu)
  cases[[length(cases) + 1]] <- case("pcor", c(p, nu, u, rowm(S)), pcor(u, S), rel = 1e-9, abs = 1e-11)
  P <- parcor(S)
  for (i in 1:p) for (j in 1:p) cases[[length(cases) + 1]] <- case("parcor", c(p, rowm(S), i - 1, j - 1), P[i, j], rel = 1e-9, abs = 1e-11)
  r <- round(runif(1, -0.9, 0.9), 3); q <- sample(0:3, 1); nn <- sample(10:60, 1); t <- pcor.test(r, q, nn)
  cases[[length(cases) + 1]] <- case("pctest", c(r, q, nn, 0), t$tval, rel = 1e-9, abs = 1e-11)
  cases[[length(cases) + 1]] <- case("pctest", c(r, q, nn, 1), t$df, rel = 1e-9, abs = 1e-11)
  cases[[length(cases) + 1]] <- case("pctest", c(r, q, nn, 2), t$pvalue, rel = 1e-9, abs = 1e-13)
}
for (rep in 1:20) {
  p <- sample(3:6, 1); n <- sample(40:120, 1)
  A <- matrix(0, p, p); for (i in 1:(p - 1)) for (j in (i + 1):p) A[i, j] <- rbinom(1, 1, 0.5)
  dimnames(A) <- list(letters[1:p], letters[1:p])
  # data from the DAG so the fit is not degenerate
  x <- matrix(0, n, p); for (j in 1:p) { x[, j] <- rnorm(n); for (i in which(A[, j] == 1)) x[, j] <- x[, j] + 0.6 * x[, i] }
  S <- crossprod(scale(x, scale = FALSE)) / n; dimnames(S) <- list(letters[1:p], letters[1:p])
  f <- fitDag(A, S, n)
  out <- c(rowm(f$Shat), f$Dhat, f$dev, f$df, rowm(f$Ahat))
  for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("dag", c(p, n, rowm(S), rowm(A), q - 1), out[q], rel = 1e-8, abs = 1e-10)
}
for (rep in 1:20) {
  p <- sample(3:6, 1); n <- sample(40:120, 1); S <- rndS(p, n)
  A <- matrix(0, p, p); for (i in 1:(p - 1)) for (j in (i + 1):p) { e <- rbinom(1, 1, 0.5); A[i, j] <- e; A[j, i] <- e }
  if (all(A == 0)) { A[1, 2] <- 1; A[2, 1] <- 1 }
  if (all(A[upper.tri(A)] == 1)) { A[1, p] <- 0; A[p, 1] <- 0 }
  dimnames(A) <- list(letters[1:p], letters[1:p])
  f <- fitConGraph(A, S, n)
  out <- c(rowm(f$Shat), f$dev, f$df, f$it)
  for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("con", c(p, n, rowm(S), rowm(A), q - 1), out[q], rel = 1e-6, abs = 1e-8)
  f <- tryCatch(fitCovGraph(A, S, n), error = function(e) NULL)
  if (!is.null(f)) { out <- c(rowm(f$Shat), f$dev, f$df, f$it); for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("cov", c(p, n, rowm(S), rowm(A), q - 1), out[q], rel = 1e-6, abs = 1e-8) }
}
emit("ggm", "ggm", list(cases))
