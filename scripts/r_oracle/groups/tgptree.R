# tgptree: tgp::btlm (meanfn linear) and tgp::bcart (constant mean), the treed linear and constant models, under
# set.seed. Data have a jump in x1 so that trees are visited. Args: data seed, seed, n, d, nn, B, T, E, model (0 btlm,
# 1 bcart), m0r1, pred.n, improv, Ds2x, field, k. Fields: the tgpgp ones (0..20) and 21 = gpcs (grow, prune, change,
# swap acceptance rates).
library(tgp)

make_data <- function(ds, n, d, nn) {
  set.seed(ds)
  X <- matrix(runif(n * d), n, d)
  x2 <- if (d > 1) X[, 2] else rep(0, n)
  z <- ifelse(X[, 1] < 0.4, 1 + 2 * x2, -1 + sin(8 * X[, 1]) + 0.5 * x2)
  if (d > 2) for (j in 3:d) z <- z + 0.3 * X[, j]
  Z <- z + 0.1 * rnorm(n)
  XX <- matrix(runif(nn * d), nn, d)
  list(X = X, Z = Z, XX = XX)
}

configs <- list(
  list(ds = 31, seed = 4, n = 70, d = 2, nn = 8, B = 200, T = 800, E = 2, md = 0, m0 = 1, pn = 1, im = 1, dsx = 1),
  list(ds = 32, seed = 9, n = 60, d = 1, nn = 6, B = 150, T = 600, E = 2, md = 0, m0 = 1, pn = 1, im = 1, dsx = 1),
  list(ds = 33, seed = 12, n = 80, d = 3, nn = 7, B = 200, T = 700, E = 2, md = 0, m0 = 0, pn = 0, im = 1, dsx = 1),
  list(ds = 34, seed = 6, n = 70, d = 2, nn = 8, B = 200, T = 800, E = 2, md = 1, m0 = 1, pn = 1, im = 1, dsx = 1),
  list(ds = 35, seed = 21, n = 60, d = 1, nn = 6, B = 150, T = 600, E = 2, md = 1, m0 = 1, pn = 0, im = 1, dsx = 0),
  list(ds = 36, seed = 3, n = 90, d = 2, nn = 8, B = 250, T = 910, E = 3, md = 1, m0 = 0, pn = 1, im = 1, dsx = 1)
)

cases <- list()
for (cf in configs) {
  dat <- make_data(cf$ds, cf$n, cf$d, cf$nn)
  set.seed(cf$seed)
  if (cf$md == 0) {
    fit <- btlm(dat$X, dat$Z, dat$XX, BTE = c(cf$B, cf$T, cf$E), m0r1 = cf$m0 == 1, pred.n = cf$pn == 1,
                improv = cf$im == 1, Ds2x = cf$dsx == 1, verb = 0)
  } else {
    fit <- bcart(dat$X, dat$Z, dat$XX, BTE = c(cf$B, cf$T, cf$E), m0r1 = cf$m0 == 1, pred.n = cf$pn == 1,
                 improv = cf$im == 1, Ds2x = cf$dsx == 1, verb = 0)
  }
  fields <- list(fit$ZZ.mean, fit$ZZ.q1, fit$ZZ.med, fit$ZZ.q2, fit$ZZ.q, fit$ZZ.s2, fit$ZZ.km, fit$ZZ.ks2,
                 fit$ZZ.vark, fit$Zp.mean, fit$Zp.q1, fit$Zp.med, fit$Zp.q2, fit$Zp.q, fit$Zp.s2, fit$Zp.km,
                 fit$Zp.ks2, fit$Zp.vark, fit$Ds2x, if (is.null(fit$improv)) NULL else fit$improv$improv,
                 if (is.null(fit$improv)) NULL else fit$improv$rank, as.numeric(fit$gpcs), fit$posts$lpost,
                 c(nrow(fit$posts), fit$posts$height[which.max(fit$posts$lpost)]))
  for (fi in seq_along(fields)) {
    v <- fields[[fi]]
    if (is.null(v)) next
    for (k in seq_along(v)) {
      if (is.nan(v[k])) next
      cases[[length(cases) + 1]] <- list(case("btlm",
        c(cf$ds, cf$seed, cf$n, cf$d, cf$nn, cf$B, cf$T, cf$E, cf$md, cf$m0, cf$pn, cf$im, cf$dsx, fi - 1, k - 1),
        v[k], rel = if (fi == 23) 1e-5 else 1e-9, abs = 1e-12))
    }
  }
}

emit("tgptree", "tgp", cases)
