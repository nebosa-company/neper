# tgptreegp: tgp::btgp (md 0) and tgp::btgpllm (md 1, gamma = c(10, 0.2, 0.7)), the treed Gaussian process with the
# separable exponential correlation, under set.seed. Data as in tgptree. Args: data seed, seed, n, d, nn, B, T, E,
# model, linear mean (1) or constant (0), m0r1, pred.n, improv, Ds2x, jump, noise, field, k. Fields: the tgpgp ones (0..20) and
# 21 = gpcs (grow, prune, change, swap acceptance rates).
library(tgp)

make_data <- function(ds, n, d, nn, jump, noise) {
  set.seed(ds)
  X <- matrix(runif(n * d), n, d)
  x2 <- if (d > 1) X[, 2] else rep(0, n)
  z <- ifelse(X[, 1] < 0.45, 1 + 0.5 * x2, 1 + jump + sin(10 * X[, 1]) + 0.5 * x2)
  if (d > 2) for (j in 3:d) z <- z + 0.3 * X[, j]
  Z <- z + noise * rnorm(n)
  XX <- matrix(runif(nn * d), nn, d)
  list(X = X, Z = Z, XX = XX)
}

configs <- list(
  list(ds = 53, seed = 7, n = 80, d = 2, nn = 6, B = 100, T = 500, E = 2, md = 0, lin = 1, m0 = 1, pn = 1, im = 1, dsx = 1, jump = 3, noise = 0.02),
  list(ds = 54, seed = 7, n = 60, d = 1, nn = 6, B = 100, T = 500, E = 2, md = 1, lin = 1, m0 = 1, pn = 1, im = 1, dsx = 1, jump = 3, noise = 0.02),
  list(ds = 51, seed = 7, n = 70, d = 1, nn = 6, B = 100, T = 500, E = 2, md = 1, lin = 1, m0 = 1, pn = 0, im = 1, dsx = 1, jump = 4, noise = 0.05),
  list(ds = 55, seed = 9, n = 70, d = 2, nn = 6, B = 100, T = 500, E = 2, md = 0, lin = 0, m0 = 0, pn = 1, im = 1, dsx = 0, jump = 4, noise = 0.02),
  list(ds = 56, seed = 11, n = 70, d = 2, nn = 6, B = 100, T = 500, E = 2, md = 1, lin = 0, m0 = 1, pn = 1, im = 1, dsx = 1, jump = 4, noise = 0.02),
  list(ds = 57, seed = 13, n = 60, d = 1, nn = 6, B = 100, T = 500, E = 2, md = 0, lin = 1, m0 = 0, pn = 0, im = 1, dsx = 1, jump = 3, noise = 0.02)
)

cases <- list()
for (cf in configs) {
  dat <- make_data(cf$ds, cf$n, cf$d, cf$nn, cf$jump, cf$noise)
  set.seed(cf$seed)
  mf <- if (cf$lin == 1) "linear" else "constant"
  if (cf$md == 0) {
    fit <- btgp(dat$X, dat$Z, dat$XX, meanfn = mf, BTE = c(cf$B, cf$T, cf$E), m0r1 = cf$m0 == 1,
                pred.n = cf$pn == 1, improv = cf$im == 1, Ds2x = cf$dsx == 1, verb = 0)
  } else {
    fit <- btgpllm(dat$X, dat$Z, dat$XX, meanfn = mf, BTE = c(cf$B, cf$T, cf$E), m0r1 = cf$m0 == 1,
                   pred.n = cf$pn == 1, improv = cf$im == 1, Ds2x = cf$dsx == 1, verb = 0)
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
      cases[[length(cases) + 1]] <- list(case("btgp",
        c(cf$ds, cf$seed, cf$n, cf$d, cf$nn, cf$B, cf$T, cf$E, cf$md, cf$lin, cf$m0, cf$pn, cf$im, cf$dsx, cf$jump, cf$noise, fi - 1, k - 1),
        v[k], rel = if (fi == 23) 1e-5 else 1e-9, abs = 1e-12))
    }
  }
}

emit("tgptreegp", "tgp", cases)
