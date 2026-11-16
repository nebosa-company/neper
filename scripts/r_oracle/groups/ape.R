# ape::nj edge lengths of the neighbour-joining tree, sorted ascending (order-free comparison).
#   args: (n, D[n*n] row-major), dissimilarities from random points (not always additive, so lengths can be negative)
#   fn "total" (sum of lengths), "sorted" (sorted lengths weighted by position)
suppressMessages(library(ape))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-10)
set.seed(20261221)
for (rep in 1:30) {
  n <- sample(4:30, 1); p <- sample(2:6, 1)
  x <- matrix(rnorm(n * p), n); d <- if (rep %% 3 == 0) as.matrix(dist(x, "manhattan")) else as.matrix(dist(x))
  d[upper.tri(d)] <- t(d)[upper.tri(d)]
  t <- nj(as.dist(d)); e <- sort(t$edge.length)
  a <- c(n, as.vector(t(d)))
  add("total", a, sum(e)); add("sorted", a, sum(e * seq_along(e)))
}
emit("ape", "ape", list(cases))
