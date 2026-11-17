# BiasedUrn random variates under set.seed: rFNCHypergeo / rWNCHypergeo (the sampling method follows the parameters and nran).
#   "rF" / "rW": (seed, nran, m1, m2, n, odds, prec, mode)  mode 0 the sum of x_i * i (i from 1), 1 the last variate
#   "rMF" / "rMW": (seed, nran, c, n, prec, mode, m[c], odds[c])  mode 0 the sum over variates v and colours j of x * (j + 1) * v, 1 the last variate's colour 0
suppressMessages(library(BiasedUrn))
cases <- list()
set.seed(20261117)
wsum <- function(x) sum(x * seq_along(x))
addu <- function(fn, seed, nran, m1, m2, n, odds, prec) {
  set.seed(seed); x <- if (fn == "rF") rFNCHypergeo(nran, m1, m2, n, odds, prec) else rWNCHypergeo(nran, m1, m2, n, odds, prec)
  a <- c(seed, nran, m1, m2, n, odds, prec)
  cases[[length(cases) + 1]] <<- case(fn, c(a, 0), wsum(x), rel = 0, abs = 0)
  cases[[length(cases) + 1]] <<- case(fn, c(a, 1), x[length(x)], rel = 0, abs = 0)
}
seed <- 100
nx <- function() { seed <<- seed + 1; seed }
for (rep in 1:3) for (fn in c("rF", "rW")) {
  # small n: Fisher inversion / Wallenius urn, one at a time and as a table
  for (nran in c(1, 3, 4, 5, 9, 40)) {
    m1 <- sample(5:60, 1); m2 <- sample(5:60, 1); n <- sample(3:min(25, m1 + m2 - 1), 1); w <- sample(c(0.2, 0.5, 1.5, 2.5, 7), 1)
    addu(fn, nx(), nran, m1, m2, n, w, 1e-7)
  }
  # mirrored urns: more red than half, more drawn than half
  addu(fn, nx(), 3, 70, 20, 12, 3, 1e-7); addu(fn, nx(), 3, 20, 70, 60, 0.4, 1e-7); addu(fn, nx(), 3, 70, 20, 80, 2.5, 1e-7)
  # n >= 30: Fisher ratio of uniforms, Wallenius table for n N < 10000, variance < 4 inversion, large nran table
  for (nran in c(1, 2, 3, 4, 6, 12, 40, 90)) {
    m1 <- sample(30:150, 1); m2 <- sample(30:150, 1); n <- sample(31:min(60, m1 + m2 - 1), 1); w <- sample(c(0.3, 0.7, 1.6, 3, 9), 1)
    addu(fn, nx(), nran, m1, m2, n, w, 1e-7)
  }
  for (nran in c(1, 2, 4, 20, 150)) {
    m1 <- sample(300:900, 1); m2 <- sample(300:900, 1); n <- sample(120:300, 1); w <- sample(c(0.3, 0.8, 1.4, 2.2, 5), 1)
    addu(fn, nx(), nran, m1, m2, n, w, 1e-7)
  }
  # extreme odds, odds 1 (hypergeometric), odds 0
  addu(fn, nx(), 3, 30, 40, 20, 1e6, 1e-7); addu(fn, nx(), 3, 30, 40, 20, 1e-7, 1e-7); addu(fn, nx(), 3, 40, 50, 20, 1, 1e-7)
  addu(fn, nx(), 3, 400, 500, 60, 1, 1e-7); addu(fn, nx(), 3, 4000, 5000, 600, 1, 1e-7); addu(fn, nx(), 3, 40, 50, 20, 0, 1e-7)
  addu(fn, nx(), 6, 100, 200, 50, 2, 1e-4)
}
emit("biasedurn_rand", "BiasedUrn", list(cases))
