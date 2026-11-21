# tgpgp: tgp::bgp (gamma[1] = 0) and tgp::bgpllm (gamma[1] > 0), the Bayesian GP with the separable exponential
# correlation and no tree, under set.seed. Data as in tgpblm. Args: data seed, seed, n, d, nn, B, T, E, linear mean (1)
# or constant (0), m0r1, pred.n, improv, Ds2x, gamma[1], field, k. Fields as in tgpblm.
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
  list(ds = 21, seed = 3, n = 20, d = 1, nn = 5, B = 40, T = 200, E = 2, lin = 1, m0 = 1, pn = 1, im = 1, dsx = 1, g0 = 0),
  list(ds = 22, seed = 8, n = 25, d = 2, nn = 6, B = 30, T = 180, E = 3, lin = 1, m0 = 0, pn = 1, im = 1, dsx = 1, g0 = 0),
  list(ds = 23, seed = 15, n = 18, d = 2, nn = 5, B = 20, T = 120, E = 2, lin = 0, m0 = 1, pn = 0, im = 1, dsx = 0, g0 = 0),
  list(ds = 24, seed = 5, n = 20, d = 1, nn = 5, B = 40, T = 200, E = 2, lin = 1, m0 = 1, pn = 1, im = 1, dsx = 1, g0 = 10),
  list(ds = 25, seed = 77, n = 25, d = 2, nn = 6, B = 30, T = 180, E = 3, lin = 1, m0 = 0, pn = 1, im = 1, dsx = 1, g0 = 10),
  list(ds = 26, seed = 31, n = 22, d = 3, nn = 4, B = 20, T = 120, E = 2, lin = 1, m0 = 1, pn = 0, im = 1, dsx = 1, g0 = 10)
)

cases <- list()
for (cf in configs) {
  dat <- make_data(cf$ds, cf$n, cf$d, cf$nn)
  set.seed(cf$seed)
  mf <- if (cf$lin == 1) "linear" else "constant"
  if (cf$g0 == 0) {
    fit <- bgp(dat$X, dat$Z, dat$XX, meanfn = mf, BTE = c(cf$B, cf$T, cf$E), m0r1 = cf$m0 == 1,
               pred.n = cf$pn == 1, improv = cf$im == 1, Ds2x = cf$dsx == 1, verb = 0)
  } else {
    fit <- bgpllm(dat$X, dat$Z, dat$XX, meanfn = mf, gamma = c(cf$g0, 0.2, 0.7), BTE = c(cf$B, cf$T, cf$E),
                  m0r1 = cf$m0 == 1, pred.n = cf$pn == 1, improv = cf$im == 1, Ds2x = cf$dsx == 1, verb = 0)
  }
  fields <- list(fit$ZZ.mean, fit$ZZ.q1, fit$ZZ.med, fit$ZZ.q2, fit$ZZ.q, fit$ZZ.s2, fit$ZZ.km, fit$ZZ.ks2,
                 fit$ZZ.vark, fit$Zp.mean, fit$Zp.q1, fit$Zp.med, fit$Zp.q2, fit$Zp.q, fit$Zp.s2, fit$Zp.km,
                 fit$Zp.ks2, fit$Zp.vark, fit$Ds2x, if (is.null(fit$improv)) NULL else fit$improv$improv,
                 if (is.null(fit$improv)) NULL else fit$improv$rank)
  for (fi in seq_along(fields)) {
    v <- fields[[fi]]
    if (is.null(v)) next
    for (k in seq_along(v))
      cases[[length(cases) + 1]] <- list(case("bgp",
        c(cf$ds, cf$seed, cf$n, cf$d, cf$nn, cf$B, cf$T, cf$E, cf$lin, cf$m0, cf$pn, cf$im, cf$dsx, cf$g0, fi - 1, k - 1),
        v[k], rel = 1e-9, abs = 1e-12))
  }
}

emit("tgpgp", "tgp", cases)
