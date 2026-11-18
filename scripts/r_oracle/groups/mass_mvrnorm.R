# MASS::mvrnorm under set.seed: the n by p draws, sums over the entries.
#   "mv" (seed, n, p, mu[p], Sigma[p p] row-major, j)   j 0 sum, 1 position-weighted sum, 2 sum of squares of the n by p result (row-major)
suppressMessages(library(MASS))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-11) if (length(want) == 1 && is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261231)
flat <- function(m) as.vector(t(unclass(m)))
sums <- function(fn, a, v, rel = 1e-9) { v <- as.numeric(v); w <- seq_along(v); add(fn, c(a, 0), sum(v), rel); add(fn, c(a, 1), sum(w * v), rel); add(fn, c(a, 2), sum(v^2), rel) }
for (rep in 1:12) {
  p <- c(2, 3, 4)[(rep - 1) %% 3 + 1]; n <- c(5, 20, 50, 100)[(rep - 1) %/% 3 + 1]
  A <- matrix(rnorm(p * p), p); Sigma <- crossprod(A) + diag(p) * 0.5
  mu <- runif(p, -2, 2); seed <- sample(1:1000000, 1)
  set.seed(seed)
  X <- mvrnorm(n, mu, Sigma)
  sums("mv", c(seed, n, p, mu, flat(Sigma)), flat(X))
}
emit("mass_mvrnorm", "MASS", list(cases))
