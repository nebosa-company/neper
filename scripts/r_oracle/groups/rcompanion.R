# rcompanion effect sizes: epsilonSquared, freemanTheta, cliffDelta, vda, cramerV and cohenW.
#   epsilon, freeman: (n, k, x[n], g[n] 0-based);  cliff, vda: (n1, n2, x, y);  cramer: (r, c, bias, table row-major); cohenw: (r, c, table)
suppressMessages(library(rcompanion))
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261127)
for (rep in 1:10) {
  k <- c(3, 4, 5)[(rep - 1) %% 3 + 1]; sz <- sample(8:20, k, TRUE); g <- rep(0:(k - 1), sz); n <- sum(sz)
  x <- round(rnorm(n, g * 0.4, 1), 1)
  add("epsilon", c(n, k, x, g), epsilonSquared(x, factor(g))); add("freeman", c(n, k, x, g), freemanTheta(x, factor(g)))
  A <- round(rnorm(sz[1], 0.5, 1), 1); B <- round(rnorm(sz[2], 0, 1.2), 1)
  add("cliff", c(length(A), length(B), A, B), cliffDelta(x = A, y = B)); add("vda", c(length(A), length(B), A, B), vda(x = A, y = B))
  r <- c(2, 3, 4)[(rep - 1) %% 3 + 1]; cc <- c(3, 2, 4)[(rep - 1) %% 3 + 1]
  tb <- matrix(rpois(r * cc, 12) + 1, r, cc)
  add("cramer", c(r, cc, 0, as.vector(t(tb))), cramerV(tb)); add("cramer", c(r, cc, 1, as.vector(t(tb))), cramerV(tb, bias.correct = TRUE))
  add("cohenw", c(r, cc, as.vector(t(tb))), cohenW(tb))
}
emit("rcompanion", "rcompanion", list(cases))
