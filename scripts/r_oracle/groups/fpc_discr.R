# fpc::discrcoord. Args: (n, p, K, pool, cl[n], x[n p] row-major, which): pool 0 "n", 1 "equal"; which 0 sum of the eigenvalues, 1 sum of the projections,
# 2 sum of index * projection (row-major), 3 sum of W, 4 sum of index * W (row-major), with W the pooled within-group covariance.
suppressMessages(library(fpc))
cases <- list()
add <- function(fn, args, want, rel = 1e-7, abs = 1e-9) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261237)
flat <- function(m) as.vector(t(unclass(m)))
for (rep in 1:12) {
  # K - 1 >= p: the between-group matrix has rank K - 1, so every axis is a real one (a zero eigenvalue has no stable eigenvector)
  p <- c(2, 3)[(rep - 1) %% 2 + 1]; K <- 4; n <- sample(30:60, 1)
  cl <- sample(1:K, n, replace = TRUE); cl[1:K] <- 1:K
  x <- matrix(rnorm(n * p), n, p) + outer(cl, seq_len(p)) * 0.9
  pool <- rep %% 2
  d <- discrcoord(x, cl, pool = c("n", "equal")[pool + 1])
  base <- c(n, p, K, pool, cl, flat(x))
  add("dc", c(base, 0), sum(d$ev))
  add("dc", c(base, 1), sum(d$proj^2))
  add("dc", c(base, 2), sum(abs(d$proj)))
  add("dc", c(base, 3), sum(flat(d$W)))
  add("dc", c(base, 4), sum(seq_along(flat(d$W)) * flat(d$W)))
  add("dc", c(base, 5), sum(d$proj[, 1]^2)); add("dc", c(base, 6), sum(d$proj[, p]^2))
  add("dc", c(base, 7), sum(abs(d$units)))
}
emit("fpc_discr", "fpc", list(cases))
