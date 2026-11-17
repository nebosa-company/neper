# BiasedUrn multivariate moments (the closed-form approximation at precision >= 0.1 and the truncated enumeration below it),
# the multivariate odds and ball-count estimators, and the univariate ball-count estimators.
#   "mom": (kind 0 Fisher 1 Wallenius, prec, what 0 mean 1 variance, idx, n, c, m[c], odds[c])
#   "om":  (kind, idx, n, c, m[c], mu[c])          oddsMFNCHypergeo / oddsMWNCHypergeo, 0-based idx
#   "num": (kind, idx, n, N, c, mu[c], odds[c])    numMFNCHypergeo / numMWNCHypergeo
#   "nu":  (kind, which 0 m1 1 m2, mu, n, N, odds) numFNCHypergeo / numWNCHypergeo
suppressMessages(library(BiasedUrn))
cases <- list()
set.seed(20261117)
add <- function(fn, a, want, tol) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, a, want, rel = tol, abs = tol)
for (rep in 1:14) {
  cc <- sample(3:5, 1); m <- sample(2:9, cc, TRUE); n <- sample(2:min(14, sum(m) - 1), 1)
  od <- round(runif(cc, 0.3, 4), 2)
  if (rep %% 5 == 0) od[sample(cc, 1)] <- 0
  if (rep %% 7 == 0) m[sample(cc, 1)] <- 0
  if (sum(m[od > 0]) <= n) next
  for (prec in c(1, 0.1, 0.05, 0.01, 1e-3, 1e-5)) for (kind in 0:1) {
    r <- suppressWarnings(if (kind == 0) momentsMFNCHypergeo(m, n, od, prec) else momentsMWNCHypergeo(m, n, od, prec))
    for (i in 1:cc) { add("mom", c(kind, prec, 0, i - 1, n, cc, m, od), r$xMean[i], 1e-9); add("mom", c(kind, prec, 1, i - 1, n, cc, m, od), r$xVariance[i], 1e-9) }
  }
}
for (rep in 1:12) {
  cc <- sample(3:5, 1); m <- sample(3:12, cc, TRUE); n <- sample(3:(sum(m) - 2), 1)
  mu <- as.numeric(rmultinom(1, 1000, m / sum(m))) / 1000 * n * 0.5 + m / sum(m) * n * 0.5
  od <- round(runif(cc, 0.3, 4), 2)
  for (kind in 0:1) {
    r <- suppressWarnings(if (kind == 0) oddsMFNCHypergeo(mu, m, n) else oddsMWNCHypergeo(mu, m, n))
    for (i in 1:cc) add("om", c(kind, i - 1, n, cc, m, mu), r[i], 1e-10)
    N <- sum(m)
    r <- suppressWarnings(if (kind == 0) numMFNCHypergeo(mu, n, N, od) else numMWNCHypergeo(mu, n, N, od))
    for (i in 1:cc) add("num", c(kind, i - 1, n, N, cc, mu, od), r[i], 1e-7)
  }
}
for (rep in 1:20) {
  N <- sample(20:200, 1); n <- sample(5:(N - 5), 1); mu <- runif(1, 0.5, n - 0.5); od <- round(runif(1, 0.2, 6), 2)
  for (kind in 0:1) {
    r <- suppressWarnings(if (kind == 0) numFNCHypergeo(mu, n, N, od) else numWNCHypergeo(mu, n, N, od))
    add("nu", c(kind, 0, mu, n, N, od), r[1], 1e-7); add("nu", c(kind, 1, mu, n, N, od), r[2], 1e-7)
  }
}
emit("biasedurn_mv", "BiasedUrn", list(cases))
