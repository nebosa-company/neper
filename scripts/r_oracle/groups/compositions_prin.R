# compositions: gsi.PrinBal with its default method "PBhclust" (the ward hclust of the variation matrix, its merges as a signary, then the ilr base).
#   "pb" (n, d, X[n d] row-major, j)   the base V (d by d - 1) row-major; j 0 sum, 1 position-weighted sum, 2 sum of squares
suppressMessages(library(compositions))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-11) if (length(want) == 1 && is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261230)
flat <- function(m) as.vector(t(unclass(m)))
sums <- function(fn, a, v, rel = 1e-9) { v <- as.numeric(v); w <- seq_along(v); add(fn, c(a, 0), sum(v), rel); add(fn, c(a, 1), sum(w * v), rel); add(fn, c(a, 2), sum(v^2), rel) }
for (rep in 1:9) {
  d <- c(3, 4, 5)[(rep - 1) %% 3 + 1]; n <- c(12, 20, 30)[(rep - 1) %/% 3 + 1]
  X <- matrix(rgamma(n * d, 2, 1) + 0.05, n, d)
  V <- compositions::gsi.PrinBal(acomp(X))
  sums("pb", c(n, d, flat(X)), flat(unclass(V)))
}
emit("compositions_prin", "compositions", list(cases))
