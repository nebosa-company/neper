# mlbench: friedman1, friedman2, friedman3, 2dnormals, circle, xor, twonorm, ringnorm under set.seed.
#   args: (kind 0 friedman1 1 friedman2 2 friedman3 3 2dnormals 4 circle 5 xor 6 twonorm 7 ringnorm, seed, n, d (or cl), p1 (sd or r), p2 (sd for 2dnormals), stat)
#   fn "x" and "y": stat 0 sum 1 position-weighted sum (row-major x) 2 sum of squares
library(mlbench)
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-10)
sums <- function(fn, a, v) { v <- as.numeric(v); w <- seq_along(v); for (j in 0:2) add(fn, c(a, j), c(sum(v), sum(w * v), sum(v^2))[j + 1]) }
for (seed in c(1, 7, 2026)) {
  for (n in c(30, 100)) {
    set.seed(seed); r <- mlbench.friedman1(n, sd = 1); a <- c(0, seed, n, 10, 1, 0); sums("x", a, t(r$x)); sums("y", a, r$y)
    set.seed(seed); r <- mlbench.friedman2(n); a <- c(1, seed, n, 4, 125, 0); sums("x", a, t(r$x)); sums("y", a, r$y)
    set.seed(seed); r <- mlbench.friedman3(n); a <- c(2, seed, n, 4, 0.1, 0); sums("x", a, t(r$x)); sums("y", a, r$y)
    for (cl in c(2, 3, 5)) { set.seed(seed); r <- mlbench.2dnormals(n, cl = cl); a <- c(3, seed, n, cl, sqrt(cl), 1); sums("x", a, t(r$x)); sums("y", a, as.numeric(as.character(r$classes))) }
    for (d in c(2, 3, 5)) {
      set.seed(seed); r <- mlbench.circle(n, d); a <- c(4, seed, n, d, 0, 0); sums("x", a, t(r$x)); sums("y", a, as.numeric(as.character(r$classes)))
      set.seed(seed); r <- mlbench.xor(n, d); a <- c(5, seed, n, d, 0, 0); sums("x", a, t(r$x)); sums("y", a, as.numeric(as.character(r$classes)))
    }
    for (d in c(4, 20)) {
      set.seed(seed); r <- mlbench.twonorm(n, d); a <- c(6, seed, n, d, 0, 0); sums("x", a, t(r$x)); sums("y", a, as.numeric(as.character(r$classes)))
      set.seed(seed); r <- mlbench.ringnorm(n, d); a <- c(7, seed, n, d, 0, 0); sums("x", a, t(r$x)); sums("y", a, as.numeric(as.character(r$classes)))
    }
  }
}
emit("mlbench", "mlbench", list(cases))
