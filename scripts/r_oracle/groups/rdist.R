# R's random variates: rgamma, rchisq, rt, rbeta, rbinom, rpois, rnbinom (size, prob and mu), rgeom,
# rweibull, rlnorm, rlogis, rcauchy. A case is (dist, seed, p1, p2, i): after set.seed(seed) the ith
# (0-based) of 15 draws. dist: 0 gamma(shape, scale) 1 chisq(df) 2 t(df) 3 beta(a, b) 4 binom(n, p)
# 5 pois(mu) 6 nbinom(size, prob) 7 nbinom_mu(size, mu) 8 geom(p) 9 weibull(shape, scale)
# 10 lnorm(meanlog, sdlog) 11 logis(location, scale) 12 cauchy(location, scale)
set.seed(1)
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-12, abs = 1e-300)
N <- 15
draw <- function(d, seed, p1, p2) {
  set.seed(seed)
  switch(d + 1,
    rgamma(N, p1, scale = p2), rchisq(N, p1), rt(N, p1), rbeta(N, p1, p2), rbinom(N, p1, p2), rpois(N, p1),
    rnbinom(N, p1, p2), rnbinom(N, p1, mu = p2), rgeom(N, p1), rweibull(N, p1, p2), rlnorm(N, p1, p2),
    rlogis(N, p1, p2), rcauchy(N, p1, p2))
}
grid <- list(
  list(0, c(0.05, 0.3, 0.9, 1, 1.5, 3.5, 3.7, 10, 13, 13.1, 50, 500), c(0.5, 1, 7)),
  list(1, c(0.5, 1, 3, 10, 100), 0), list(2, c(0.5, 1, 3, 30, 1e10, Inf), 0),
  list(3, NULL, NULL), list(4, NULL, NULL), list(5, c(0.1, 0.5, 1, 3, 9.9, 10, 10.5, 25, 100, 1000, 1e5), 0),
  list(6, NULL, NULL), list(7, NULL, NULL), list(8, c(0.01, 0.1, 0.5, 0.9, 1), 0),
  list(9, NULL, NULL), list(10, NULL, NULL), list(11, NULL, NULL), list(12, NULL, NULL))
pairs <- list(
  `3` = list(c(0.3, 0.5), c(0.5, 2), c(1, 1), c(2, 3), c(1, 5), c(5, 1), c(0.9, 0.2), c(10, 10), c(0.01, 0.01), c(100, 200), c(0, 0), c(0, 1), c(1, 0), c(Inf, Inf), c(0.5, 0.5), c(3, 0.7)),
  `4` = list(c(1, 0.5), c(10, 0.3), c(10, 0.7), c(50, 0.5), c(100, 0.3), c(100, 0.9), c(1000, 0.5), c(200, 0.1), c(5, 0.001), c(0, 0.5), c(10, 0), c(10, 1), c(3000, 0.45), c(60, 0.5)),
  `6` = list(c(1, 0.5), c(5, 0.3), c(0.5, 0.9), c(100, 0.5), c(3, 1)),
  `7` = list(c(2, 3), c(10, 100), c(0.5, 0.2), c(5, 0)),
  `9` = list(c(1, 1), c(2, 3), c(0.5, 2), c(10, 1)),
  `10` = list(c(0, 1), c(1, 0.5), c(-2, 2)),
  `11` = list(c(0, 1), c(2, 3), c(-1, 0.5), c(0, 0)),
  `12` = list(c(0, 1), c(1, 2), c(-3, 0.1), c(0, 0)))
for (g in grid) {
  d <- g[[1]]
  ps <- if (is.null(g[[2]])) pairs[[as.character(d)]] else {
    lapply(as.vector(outer(g[[2]], g[[3]], function(a, b) paste(a, b))), function(s) as.numeric(strsplit(s, " ")[[1]]))
  }
  for (p in ps) for (seed in c(20261115, 42, 7)) {
    v <- tryCatch(suppressWarnings(draw(d, seed, p[1], p[2])), error = function(e) NULL)
    if (is.null(v)) next
    for (i in seq_len(N)) add("rdist", c(d, seed, p[1], p[2], i - 1), as.numeric(v[i]))
  }
}
emit("rdist", character(), list(cases))
