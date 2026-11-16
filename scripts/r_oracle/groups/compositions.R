# compositions: clo, clr, alr, ilr and their inverses, the Aitchison norm and distance, perturbation, powering, mean, var, variation.
#   args: (n, d, ivar-or-power, x row-major, [y row-major], j) with j 0 sum 1 position-weighted sum 2 sum of squares of the result (row-major)
suppressMessages(library(compositions))
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-11)
set.seed(20261126)
flat <- function(m) as.vector(t(unclass(m)))
sums <- function(fn, a, v) { v <- as.numeric(v); w <- seq_along(v); add(fn, c(a, 0), sum(v)); add(fn, c(a, 1), sum(w * v)); add(fn, c(a, 2), sum(v^2)) }
for (rep in 1:8) {
  d <- c(3, 4, 5, 6)[(rep - 1) %% 4 + 1]; n <- c(12, 20, 30)[(rep - 1) %% 3 + 1]
  X <- matrix(rgamma(n * d, 2, 1) + 0.05, n, d); Y <- matrix(rgamma(n * d, 3, 1) + 0.05, n, d)
  ax <- acomp(X); ay <- acomp(Y); a0 <- c(n, d, 0)
  sums("clo", c(a0, flat(X)), flat(unclass(clo(X))))
  sums("clr", c(a0, flat(X)), flat(clr(ax)))
  Z <- unclass(ilr(ax)); sums("ilr", c(a0, flat(X)), flat(Z))
  sums("ilrinv", c(n, d, 0, flat(Z)), flat(unclass(ilrInv(Z))))
  for (iv in c(d, 1)) { Al <- unclass(alr(ax, ivar = iv)); sums("alr", c(n, d, iv - 1, flat(X)), flat(Al)); sums("alrinv", c(n, d, iv - 1, flat(Al)), flat(unclass(alrInv(Al, orig = ax)))) }
  sums("clrinv", c(n, d, 0, flat(unclass(clr(ax)))), flat(unclass(clrInv(unclass(clr(ax))))))
  add("norm", c(n, d, 0, flat(X), 0), sum(norm(ax))); add("norm", c(n, d, 0, flat(X), 1), sum(seq_len(n) * norm(ax)))
  dd <- as.numeric(norm(ax - ay)); add("dist", c(n, d, 0, flat(X), flat(Y), 0), sum(dd)); add("dist", c(n, d, 0, flat(X), flat(Y), 1), sum(seq_len(n) * dd))
  sums("perturb", c(n, d, 0, flat(X), flat(Y)), flat(unclass(ax + ay)))
  for (p in c(0.5, -2)) sums("power", c(n, d, p, flat(X)), flat(unclass(ax * p)))
  sums("mean", c(n, d, 0, flat(X)), as.numeric(unclass(mean(ax))))
  sums("var", c(n, d, 0, flat(X)), flat(var(ax))); sums("variation", c(n, d, 0, flat(X)), flat(variation(ax)))
}
emit("compositions", "compositions", list(cases))
