# norm: em.norm (mean and covariance on the original scale, default criterion 1e-4) and loglik.norm, for data with missing values.
#   args: (n, p, criterion, x[n*p] column-major, NaN = missing, q)  q 0..p-1 mu, p..p+p*p-1 sigma (row-major), then loglik
suppressMessages(library(norm))
cases <- list()
set.seed(20261116)
for (rep in 1:25) {
  n <- sample(30:120, 1); p <- sample(2:4, 1)
  L <- matrix(rnorm(p * p), p, p); S <- crossprod(L) + diag(p)
  x <- matrix(rnorm(n * p), n, p) %*% chol(S) + rep(1:p, each = n)
  x <- round(x, 3); miss <- sample(n * p, round(0.15 * n * p)); x[miss] <- NA
  keep <- rowSums(!is.na(x)) > 0; x <- x[keep, , drop = FALSE]; n <- nrow(x)
  crit <- c(1e-4, 1e-8)[rep %% 2 + 1]
  s <- prelim.norm(x); th <- em.norm(s, showits = FALSE, criterion = crit); g <- getparam.norm(s, th)
  xa <- ifelse(is.na(x), NaN, x)
  out <- c(g$mu, as.vector(t(g$sigma)), loglik.norm(s, th))
  a <- c(n, p, crit, as.vector(xa))
  for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("em", c(a, q - 1), out[q], rel = 1e-8, abs = 1e-9)
}
emit("norm", "norm", list(cases))
