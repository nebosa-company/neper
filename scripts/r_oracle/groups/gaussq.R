# statmod gauss.quad and gauss.quad.prob: every node and weight.
#   args: (fn id, n, p1, p2, p3, p4, i)  gauss.quad: id 0..5 kinds, p1 alpha, p2 beta; gauss.quad.prob: id 10..15 dists uniform beta1 beta2 normal beta gamma,
#   p1 l / mu / alpha, p2 u / sigma / beta; fn "node" "weight" (index i)
suppressMessages(library(statmod))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
kinds <- c("legendre", "chebyshev1", "chebyshev2", "hermite", "jacobi", "laguerre")
dists <- c("uniform", "beta1", "beta2", "normal", "beta", "gamma")
for (n in c(1, 2, 3, 5, 8, 15, 30)) {
  for (k in 0:5) {
    al <- c(0, 0, 0, 0, 0.7, 1.3)[k + 1]; be <- c(0, 0, 0, 0, 1.9, 0)[k + 1]
    r <- gauss.quad(n, kinds[k + 1], alpha = al, beta = be)
    for (i in seq_len(n)) { add("node", c(k, n, al, be, 0, 0, i - 1), r$nodes[i]); add("weight", c(k, n, al, be, 0, 0, i - 1), r$weights[i]) }
  }
  for (d in 0:5) {
    p1 <- c(-1, 0, 0, 2, 2.5, 3)[d + 1]; p2 <- c(4, 0, 0, 1.5, 1.2, 0.8)[d + 1]
    r <- if (d == 0) gauss.quad.prob(n, dists[d + 1], l = p1, u = p2) else if (d == 3) gauss.quad.prob(n, dists[d + 1], mu = p1, sigma = p2) else if (d >= 4) gauss.quad.prob(n, dists[d + 1], alpha = p1, beta = p2) else gauss.quad.prob(n, dists[d + 1])
    for (i in seq_len(n)) { add("node", c(10 + d, n, p1, p2, 0, 0, i - 1), r$nodes[i]); add("weight", c(10 + d, n, p1, p2, 0, 0, i - 1), r$weights[i]) }
  }
}
emit("gaussq", "statmod", list(cases))
