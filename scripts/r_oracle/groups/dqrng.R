# dqrng: dqrunif of the xoroshiro and xoshiro generators after dqset.seed.
#   args: (kind 0 Xoroshiro128+ 1 Xoroshiro128++ 2 Xoshiro256+ 3 Xoshiro256++, seed, min, max, i)   the i-th (0-based) of 12 draws
library(dqrng)
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("dqrunif", args, want, rel = 1e-15, abs = 1e-300)
kinds <- c("Xoroshiro128+", "Xoroshiro128++", "Xoshiro256+", "Xoshiro256++")
for (k in 0:3) for (seed in c(1, 42, 2026, 123456789)) for (rg in list(c(0, 1), c(-3, 5.5))) {
  dqRNGkind(kinds[k + 1]); dqset.seed(seed)
  v <- dqrunif(12, rg[1], rg[2])
  for (i in 1:12) add(c(k, seed, rg, i - 1), v[i])
}
emit("dqrng", "dqrng", list(cases))
