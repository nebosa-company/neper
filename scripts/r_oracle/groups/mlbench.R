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
#   kinds 8 cassini (relsize in slots 3-5), 9 hypercube (d, sd, side), 10 peak (d), 11 shapes, 12 simplex centred (d, sd, side), 13 smiley (sd1 sd2 in 4-5),
#   14 spirals (cycles, sd in 3-4), 15 threenorm (d), 16 waveform, 17 simplex not centred
cls <- function(r) as.numeric(as.character(r$classes))
for (seed in c(3, 11)) for (n in c(40, 100, 160)) {
  set.seed(seed); r <- mlbench.cassini(n); a <- c(8, seed, n, 2, 2, 1); sums("x", a, t(r$x)); sums("y", a, cls(r))
  set.seed(seed); r <- mlbench.cassini(n, relsize = c(3, 1, 2)); a <- c(8, seed, n, 3, 1, 2); sums("x", a, t(r$x)); sums("y", a, cls(r))
  for (d in c(2, 3)) {
    set.seed(seed); r <- mlbench.hypercube(n, d, sd = 0.2, sides = rep(2, d)); a <- c(9, seed, n, d, 0.2, 2); sums("x", a, t(r$x)); sums("y", a, cls(r))
    set.seed(seed); r <- mlbench.simplex(n, d, sides = 2, sd = 0.15); a <- c(12, seed, n, d, 0.15, 2); sums("x", a, t(r$x)); sums("y", a, cls(r))
    set.seed(seed); r <- mlbench.simplex(n, d, sides = 1.5, sd = 0.1, center = FALSE); a <- c(17, seed, n, d, 0.1, 1.5); sums("x", a, t(r$x)); sums("y", a, cls(r))
  }
  for (d in c(5, 20)) { set.seed(seed); r <- mlbench.peak(n, d); a <- c(10, seed, n, d, 0, 0); sums("x", a, t(r$x)); sums("y", a, r$y) }
  set.seed(seed); r <- mlbench.shapes(n); a <- c(11, seed, n, 0, 0, 0); sums("x", a, t(r$x)); sums("y", a, cls(r))
  set.seed(seed); r <- mlbench.smiley(n, sd1 = 0.1, sd2 = 0.05); a <- c(13, seed, n, 0, 0.1, 0.05); sums("x", a, t(r$x)); sums("y", a, cls(r))
  for (sd in c(0, 0.05)) { set.seed(seed); r <- mlbench.spirals(n, cycles = 1.5, sd = sd); a <- c(14, seed, n, 1.5, sd, 0); sums("x", a, t(r$x)); sums("y", a, cls(r)) }
  for (d in c(5, 20, 7)) { set.seed(seed); r <- mlbench.threenorm(n, d); a <- c(15, seed, n, d, 0, 0); sums("x", a, t(r$x)); sums("y", a, cls(r)) }
  set.seed(seed); r <- mlbench.waveform(n); a <- c(16, seed, n, 0, 0, 0); sums("x", a, t(r$x)); sums("y", a, cls(r))
}
emit("mlbench", "mlbench", list(cases))
