# mclust: nMclustParams, bic, adjustedRandIndex, map.
#   "npar" (model index, d, G, noise, equalPro) "bic" (model index, loglik, n, d, G, noise, equalPro) "ari" (n, x[n], y[n] as 0-based codes) "map" (n, k, z[n k] column-major, position)
suppressMessages(library(mclust))
cases <- list()
add <- function(fn, args, want, tol = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = tol, abs = 1e-12)
set.seed(20261118)
mods <- c("E", "V", "EII", "VII", "EEI", "VEI", "EVI", "VVI", "EEE", "EVE", "VEE", "VVE", "EEV", "VEV", "EVV", "VVV")
for (rep in 1:60) {
  mi <- sample(length(mods), 1); m <- mods[mi]; d <- if (mi <= 2) 1 else sample(2:6, 1); g <- sample(1:7, 1); no <- sample(c(TRUE, FALSE), 1); ep <- sample(c(TRUE, FALSE), 1)
  add("npar", c(mi - 1, d, g, no, ep), nMclustParams(m, d, g, no, ep)); n <- sample(30:500, 1); ll <- -runif(1, 50, 900)
  add("bic", c(mi - 1, ll, n, d, g, no, ep), bic(m, ll, n, d, g, no, ep))
}
for (rep in 1:40) {
  n <- sample(10:200, 1); kx <- sample(1:5, 1); ky <- sample(1:5, 1); x <- sample(kx, n, TRUE); y <- if (rep %% 3 == 0) x else sample(ky, n, TRUE)
  x <- match(x, sort(unique(x))); y <- match(y, sort(unique(y))); add("ari", c(n, x - 1, y - 1), adjustedRandIndex(x, y))
}
for (rep in 1:20) {
  n <- sample(5:40, 1); k <- sample(2:5, 1); z <- matrix(runif(n * k), n, k); z <- z / rowSums(z); z[sample(n, 1), 1:2] <- 0.5; mp <- map(z, warn = FALSE)
  for (i in seq_len(n)) add("map", c(n, k, z, i - 1), mp[i])
}
emit("mclust", "mclust", list(cases))
