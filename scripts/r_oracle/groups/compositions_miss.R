# compositions: missing and zero parts in acomp data and the seeded generators. The last argument is j: 0 sum, 1 position-weighted sum, 2 sum of squares of the (row-major) result.
#   "miss"  (kind, n, d, X[n d] row-major, j)   kind 0 mean.acomp with missing parts 1 var.acomp (complete rows) 2 cdt.acomp
#   "rn"    (kind, n, d, seed, mean[d], var[d d] row-major, alpha[d], j)   kind 0 rnorm.acomp 1 rnorm.rcomp 2 rDirichlet.acomp
suppressMessages(library(compositions))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-11) if (length(want) == 1 && is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261205)
flat <- function(m) as.vector(t(unclass(m)))
sums <- function(fn, a, v, rel = 1e-9) { v <- as.numeric(v); w <- seq_along(v); add(fn, c(a, 0), sum(v), rel); add(fn, c(a, 1), sum(w * v), rel); add(fn, c(a, 2), sum(v^2), rel) }
mk <- function(n, d) matrix(rgamma(n * d, 2, 1) + 0.05, n, d)
for (rep in 1:9) {
  d <- c(3, 4, 5)[(rep - 1) %% 3 + 1]; n <- c(14, 20, 30)[(rep - 1) %/% 3 + 1]; X <- mk(n, d)
  X[sample(n * d, n %/% 3)] <- NA; X[sample(n * d, 2)] <- 0
  if (any(rowSums(is.finite(X) & X > 0) < 2)) next
  A <- acomp(X)
  sums("miss", c(0, n, d, flat(X)), as.numeric(unclass(mean(A))))
  sums("miss", c(1, n, d, flat(X)), flat(unclass(var(A))))
  sums("miss", c(2, n, d, flat(X)), flat(unclass(cdt(A))))
}
for (rep in 1:9) {
  kind <- (rep - 1) %% 3; d <- c(3, 4, 5)[(rep - 1) %/% 3 + 1]; n <- sample(8:20, 1); seed <- sample(1:1e6, 1)
  Y <- mk(30, d); mu <- as.numeric(unclass(mean(acomp(Y)))); vr <- unclass(var(acomp(Y))); alpha <- runif(d, 0.5, 4)
  set.seed(seed)
  r <- switch(kind + 1, rnorm.acomp(n, acomp(mu), vr), rnorm.rcomp(n, rcomp(mu), vr), rDirichlet.acomp(n, alpha))
  sums("rn", c(kind, n, d, seed, mu, flat(vr), alpha), flat(unclass(r)), rel = 1e-8)
}
emit("compositions_miss", "compositions", list(cases))
