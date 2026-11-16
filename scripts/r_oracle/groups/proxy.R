# proxy: the native value of each measure for two vectors (simil for the binary and angular families, dist for
# the metric ones). args: (id, p, n, x..., y...); ids as in e.algo.stat.proxy: 0-19 binary (Jaccard, Kulczynski1,
# Kulczynski2, Mountford, Fager, Russel, simple matching, Hamman, Faith, Tanimoto, Dice, Phi, Stiles, Michael,
# Mozley, Yule, Yule2, Ochiai, Simpson, Braun-Blanquet), 20 cosine, 21 angular, 22 eJaccard, 23 eDice,
# 24 correlation, 25 Euclidean, 26 Bhattacharyya, 27 Manhattan, 28 supremum, 29 Minkowski, 30 Canberra,
# 31 Wave, 32 divergence, 33 Kullback, 34 Bray, 35 Soergel, 36 Podani, 37 Chord, 38 Geodesic, 39 Whittaker,
# 40 Hellinger, 41 fJaccard
library(proxy)
set.seed(20261115)
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("proxy", args, want, rel = 1e-11, abs = 1e-12)
names_ <- c("Jaccard", "Kulczynski1", "Kulczynski2", "Mountford", "Fager", "Russel", "simple matching", "Hamman", "Faith",
  "Tanimoto", "Dice", "Phi", "Stiles", "Michael", "Mozley", "Yule", "Yule2", "Ochiai", "Simpson", "Braun-Blanquet",
  "cosine", "angular", "eJaccard", "eDice", "correlation", "Euclidean", "Bhjattacharyya", "Manhattan", "supremum",
  "Minkowski", "Canberra", "Wave", "divergence", "Kullback", "Bray", "Soergel", "Podani", "Chord", "Geodesic",
  "Whittaker", "Hellinger", "fJaccard")
run <- function(id, m, p) {
  nm <- names_[id + 1]
  v <- tryCatch(suppressWarnings(if (id < 25 && id != 24 || id %in% c(20, 21, 22, 23, 24)) as.numeric(simil(m, nm))
        else if (id == 29) as.numeric(dist(m, nm, p = p)) else as.numeric(dist(m, nm))), error = function(e) NA)
  v
}
bins <- list()
for (i in 1:12) bins[[i]] <- rbind(rbinom(12, 1, 0.5), rbinom(12, 1, 0.4 + 0.03 * i))
bins[[13]] <- rbind(c(1, 1, 0, 0, 1, 0), c(1, 0, 1, 0, 1, 1))
bins[[14]] <- rbind(c(1, 1, 1, 1), c(1, 1, 1, 1))
bins[[15]] <- rbind(c(1, 0, 1, 0, 1, 1, 0, 1), c(0, 1, 0, 1, 0, 0, 1, 0))
for (m in bins) for (id in 0:19) {
  v <- run(id, m, 2)
  if (is.finite(v) || is.nan(v) || is.infinite(v)) add(c(id, 2, ncol(m), m[1, ], m[2, ]), v)
}
for (k in 1:10) {
  m <- rbind(round(runif(7, 0.1, 5), 2), round(runif(7, 0.1, 5), 2))
  mneg <- rbind(round(rnorm(7), 2), round(rnorm(7), 2))
  mz <- rbind(c(0, 2, 0, 3, 1, 0, 4), c(1, 0, 0, 5, 2, 0, 1))
  mf <- rbind(round(runif(7), 3), round(runif(7), 3))
  for (id in 20:41) {
    for (mm in list(m, mneg, mz, mf)) {
      if (id %in% c(26, 33, 40) && any(mm < 0)) next
      if (id == 41 && any(mm > 1 | mm < 0)) next
      for (p in if (id == 29) c(1, 3, 0.5) else 2) {
        v <- run(id, mm, p)
        if (length(v) == 1 && !is.na(v)) add(c(id, p, ncol(mm), mm[1, ], mm[2, ]), v)
      }
    }
  }
}
emit("proxy", "proxy", list(cases))
