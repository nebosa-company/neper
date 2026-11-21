# tgpblm: tgp::blm, the Bayesian linear model, under set.seed. The data are drawn in R from a data seed
# (X = matrix(runif(n d), n, d); Z = sin(4 x1) + sum_{j>=2} j x_j / 2 + 0.1 rnorm(n); XX = matrix(runif(nn d), nn, d)),
# and the fixture rebuilds them from the same seed with R's generator, so a case is small.
# Args: data seed, seed, n, d, nn, B, T, E, linear mean (1) or constant (0), m0r1, pred.n, improv, Ds2x, field, k.
# Fields (k-th value): 0 ZZ.mean 1 ZZ.q1 2 ZZ.med 3 ZZ.q2 4 ZZ.q 5 ZZ.s2 6 ZZ.km 7 ZZ.ks2 8 ZZ.vark
# 9 Zp.mean 10 Zp.q1 11 Zp.med 12 Zp.q2 13 Zp.q 14 Zp.s2 15 Zp.km 16 Zp.ks2 17 Zp.vark 18 Ds2x 19 improv 20 irank.
library(tgp)

make_data <- function(ds, n, d, nn) {
  set.seed(ds)
  X <- matrix(runif(n * d), n, d)
  z <- sin(4 * X[, 1])
  if (d > 1) for (j in 2:d) z <- z + 0.5 * j * X[, j]
  Z <- z + 0.1 * rnorm(n)
  XX <- matrix(runif(nn * d), nn, d)
  list(X = X, Z = Z, XX = XX)
}

configs <- list(
  list(ds = 11, seed = 1, n = 20, d = 1, nn = 5, B = 50, T = 250, E = 2, lin = 1, m0 = 1, pn = 1, im = 1, dsx = 1),
  list(ds = 12, seed = 7, n = 30, d = 2, nn = 8, B = 20, T = 220, E = 2, lin = 0, m0 = 0, pn = 1, im = 1, dsx = 1),
  list(ds = 13, seed = 42, n = 25, d = 3, nn = 6, B = 40, T = 240, E = 4, lin = 1, m0 = 1, pn = 0, im = 1, dsx = 1),
  list(ds = 14, seed = 2024, n = 40, d = 2, nn = 10, B = 10, T = 90, E = 1, lin = 1, m0 = 0, pn = 1, im = 0, dsx = 0),
  list(ds = 15, seed = 99, n = 12, d = 1, nn = 4, B = 7, T = 107, E = 5, lin = 0, m0 = 1, pn = 1, im = 1, dsx = 1)
)

cases <- list()
for (cf in configs) {
  dat <- make_data(cf$ds, cf$n, cf$d, cf$nn)
  set.seed(cf$seed)
  fit <- blm(dat$X, dat$Z, dat$XX, meanfn = if (cf$lin == 1) "linear" else "constant",
             BTE = c(cf$B, cf$T, cf$E), m0r1 = cf$m0 == 1, pred.n = cf$pn == 1,
             improv = cf$im == 1, Ds2x = cf$dsx == 1, verb = 0)
  fields <- list(fit$ZZ.mean, fit$ZZ.q1, fit$ZZ.med, fit$ZZ.q2, fit$ZZ.q, fit$ZZ.s2, fit$ZZ.km, fit$ZZ.ks2,
                 fit$ZZ.vark, fit$Zp.mean, fit$Zp.q1, fit$Zp.med, fit$Zp.q2, fit$Zp.q, fit$Zp.s2, fit$Zp.km,
                 fit$Zp.ks2, fit$Zp.vark, fit$Ds2x, if (is.null(fit$improv)) NULL else fit$improv$improv,
                 if (is.null(fit$improv)) NULL else fit$improv$rank)
  for (fi in seq_along(fields)) {
    v <- fields[[fi]]
    if (is.null(v)) next
    for (k in seq_along(v))
      cases[[length(cases) + 1]] <- list(case("blm",
        c(cf$ds, cf$seed, cf$n, cf$d, cf$nn, cf$B, cf$T, cf$E, cf$lin, cf$m0, cf$pn, cf$im, cf$dsx, fi - 1, k - 1),
        v[k], rel = 1e-9, abs = 1e-12))
  }
}

emit("tgpblm", "tgp", cases)
