# FNN: entropy, KL.divergence, mutinfo (direct and indirect) with exact (brute) search.
#   args: (kind, n, p1, p2, m, K, X[n*p1], Y[...]) kind 0 entropy(X, K) 1 KL.divergence(X, Y(m x p1), K) 2 mutinfo direct (X n x p1, Y n x p2, k = K)  fn "v" with the last arg the index (0-based) into the K estimates
suppressMessages(library(FNN))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("v", args, want, rel = 1e-8, abs = 1e-10)
set.seed(20261116)
for (rep in 1:25) {
  n <- sample(40:150, 1); p1 <- sample(1:3, 1); p2 <- sample(1:2, 1); K <- sample(3:8, 1); m <- sample(40:120, 1)
  X <- matrix(rnorm(n * p1), n, p1); Y2 <- matrix(rnorm(n * p2) + 0.5 * X[, 1], n, p2); Ym <- matrix(rnorm(m * p1, 0.3, 1.2), m, p1)
  e <- entropy(X, K, "brute"); for (j in seq_len(K)) add(c(0, n, p1, p2, m, K, X, 0, j - 1), e[j])
  kl <- KL.divergence(X, Ym, K, "brute"); for (j in seq_len(K)) add(c(1, n, p1, p2, m, K, X, Ym, j - 1), kl[j])
  add(c(2, n, p1, p2, m, K, X, Y2, 0), mutinfo(X, Y2, K, direct = TRUE))
  add(c(3, n, p1, p2, m, K, X, Y2, 0), mutinfo(X, Y2, K, direct = FALSE)[K])
}
emit("fnn", "FNN", list(cases))
