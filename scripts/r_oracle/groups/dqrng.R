# dqrng: dqrunif of the xoroshiro and xoshiro generators after dqset.seed.
#   args: (kind 0 Xoroshiro128+ 1 Xoroshiro128++ 2 Xoshiro256+ 3 Xoshiro256++ 4 pcg64 5 Threefry 6 Xoroshiro128** 7 Xoshiro256**, seed, min, max, i)   the i-th (0-based) of 12 draws
library(dqrng)
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("dqrunif", args, want, rel = 1e-15, abs = 1e-300)
add2 <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-13, abs = 1e-300)
kinds <- c("Xoroshiro128+", "Xoroshiro128++", "Xoshiro256+", "Xoshiro256++", "pcg64", "Threefry")
for (k in 0:5) for (seed in c(1, 42, 2026, 123456789)) for (rg in list(c(0, 1), c(-3, 5.5))) {
  dqRNGkind(kinds[k + 1]); dqset.seed(seed)
  v <- dqrunif(12, rg[1], rg[2])
  for (i in 1:12) add(c(k, seed, rg, i - 1), v[i])
}
#   dqrnorm / dqrexp (the Boost ziggurat): (kind, seed, p1, p2, i) the i-th (0-based) of 1000 draws; i = -1 the sum, -2 the maximum, -3 the minimum
for (k in 0:5) for (seed in c(1, 7, 2026)) {
  dqRNGkind(kinds[k + 1]); dqset.seed(seed); v <- dqrnorm(1000, 0.5, 2)
  for (i in c(1:12, 100, 500, 1000)) add2("dqrnorm", c(k, seed, 0.5, 2, i - 1), v[i])
  add2("dqrnorm", c(k, seed, 0.5, 2, -1), sum(v)); add2("dqrnorm", c(k, seed, 0.5, 2, -2), max(v)); add2("dqrnorm", c(k, seed, 0.5, 2, -3), min(v))
  dqRNGkind(kinds[k + 1]); dqset.seed(seed); v <- dqrexp(1000, 3)
  for (i in c(1:12, 100, 500, 1000)) add2("dqrexp", c(k, seed, 3, 0, i - 1), v[i])
  add2("dqrexp", c(k, seed, 3, 0, -1), sum(v)); add2("dqrexp", c(k, seed, 3, 0, -2), max(v)); add2("dqrexp", c(k, seed, 3, 0, -3), min(v))
}
#   dqsample.int: (kind, seed, n, size, replace, i): the i-th (0-based) value, i = -1 the sum, -2 the sum of (position + 1) * value
for (k in 0:5) for (seed in c(1, 99)) for (cfg in list(c(10, 10, 0), c(10, 4, 0), c(50, 30, 0), c(1000, 5, 0), c(1000000, 6, 0), c(100, 20, 1), c(7, 1, 0), c(100000, 400, 0), c(2000000000, 8, 0))) {
  dqRNGkind(kinds[k + 1]); dqset.seed(seed)
  v <- dqsample.int(cfg[1], cfg[2], replace = cfg[3] == 1)
  for (i in seq_len(min(length(v), 12))) add2("dqsample", c(k, seed, cfg, i - 1), v[i])
  add2("dqsample", c(k, seed, cfg, -1), sum(as.numeric(v))); add2("dqsample", c(k, seed, cfg, -2), sum(as.numeric(v) * seq_along(v)))
}
#   streams: (kind, seed, stream, i): dqrunif after dqset.seed(seed, stream), the i-th (0-based) of 8 draws
for (k in 0:5) for (seed in c(1, 2026)) for (stream in c(0, 1, 2, 5)) {
  dqRNGkind(kinds[k + 1]); dqset.seed(seed, stream)
  v <- dqrunif(8)
  for (i in 1:8) add2("dqstream", c(k, seed, stream, i - 1), v[i])
}
#   dqrng_get_state: (kind, seed, draws, word, what) what 0 the number of digits, 1 the digit sum, after dqrunif(draws) (draws 0 is none)
for (k in 0:5) for (seed in c(1, 99)) for (dr in c(0, 3)) {
  dqRNGkind(kinds[k + 1]); dqset.seed(seed); if (dr > 0) invisible(dqrunif(dr))
  w <- dqrng_get_state()[-1]
  for (j in seq_along(w)) {
    dg <- as.integer(strsplit(w[j], "")[[1]])
    add2("dqstate", c(k, seed, dr, j - 1, 0), length(dg)); add2("dqstate", c(k, seed, dr, j - 1, 1), sum(dg))
  }
}
emit("dqrng", "dqrng", list(cases))
