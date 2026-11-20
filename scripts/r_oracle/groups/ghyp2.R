# ghyp2: GeneralizedHyperbolic, second part (e.algo.stat.ghyp2).
#   "ibf" (x, y, nu, tol, nmax): DistributionUtils::incompleteBesselK
#   "qgig" (p, chi, psi, lambda, method 0 spline / 1 integrate)
suppressMessages(library(GeneralizedHyperbolic))
suppressMessages(library(DistributionUtils))
cases <- list()
nowarn <- function(expr) tryCatch(withCallingHandlers(expr, warning = function(w) stop("warn")), error = function(e) NA_real_)
set.seed(20262101)
for (rep in 1:25) {
  x <- runif(1, 0.1, 4); y <- runif(1, 0.1, 4); nu <- runif(1, -2.5, 2.5)
  tl <- c(1e-4, 1e-8, 1e-12)[sample(1:3, 1)]
  v <- nowarn(incompleteBesselK(x, y, nu, tol = tl, nmax = 200))
  if (is.finite(v)) cases[[length(cases) + 1]] <- case("ibf", c(x, y, nu, tl, 200), v, rel = 1e-9, abs = 1e-14)
}
for (rep in 1:14) {
  chi <- runif(1, 0.3, 3); psi <- runif(1, 0.3, 3); lam <- runif(1, -2, 2.5)
  for (pp in c(0.02, 0.1, 0.5, 0.9, 0.98)) {
    v <- nowarn(qgig(pp, chi, psi, lam))
    if (is.finite(v)) cases[[length(cases) + 1]] <- case("qgig", c(pp, chi, psi, lam, 0), v, rel = 1e-9, abs = 1e-11)
  }
  for (pp in c(0.001, 0.3, 0.7, 0.9995)) {
    v <- nowarn(qgig(pp, chi, psi, lam, method = "integrate"))
    if (is.finite(v)) cases[[length(cases) + 1]] <- case("qgig", c(pp, chi, psi, lam, 1), v, rel = 1e-9, abs = 1e-12)
  }
}
# "gigcheck" (chi, psi, lambda) and "ghypcheck" (delta, alpha, beta, lambda): the case codes of gigCheckPars (normal 0, gamma 1, invgamma 2, error 3) and
# ghypCheckPars (normal 0, error 1, skew laplace 2, laplace 3, hyperbolic 4, variance gamma 5, cauchy 6, nig 7, skew hyperbolic 8, student's t 9)
gcode <- function(par) { r <- gigCheckPars(par)$case; match(r, c("normal", "gamma", "invgamma", "error")) - 1 }
hcode <- function(par) { r <- ghypCheckPars(par)$case; match(r, c("normal", "error", "skew laplace", "laplace", "hyperbolic", "variance gamma", "cauchy", "normal inverse gaussian", "skew hyperbolic", "student's t")) - 1 }
for (chi in c(0, 1e-9, 0.5, 2)) for (psi in c(0, 1e-9, 0.7, 3)) for (lam in c(-1.5, 0, 0.8)) {
  cases[[length(cases) + 1]] <- case("gigcheck", c(chi, psi, lam), gcode(c(chi, psi, lam)), rel = 0, abs = 0)
}
for (de in c(0, 0.5, 2)) for (al in c(0, 1, 2)) for (be in c(0, 0.5, 1, 2, 3)) for (lam in c(-2, -0.5, 0, 0.5, 1, 2)) {
  cases[[length(cases) + 1]] <- case("ghypcheck", c(de, al, be, lam), hcode(c(0, de, al, be, lam)), rel = 0, abs = 0)
}
# "gigrawcase" (order, chi, psi, lambda): gigRawMom including chi = 0 or psi = 0; "gigmom" (order, about, chi, psi, lambda); "gigvar2", "gigskew", "gigkurt" (0, chi, psi, lambda)
set.seed(20262102)
for (rep in 1:20) {
  chi <- runif(1, 0.3, 3); psi <- runif(1, 0.3, 3); lam <- runif(1, -2, 2.5)
  for (ord in 1:4) {
    cases[[length(cases) + 1]] <- case("gigrawcase", c(ord, chi, psi, lam), gigRawMom(ord, chi, psi, lam), rel = 1e-10, abs = 1e-13)
    cases[[length(cases) + 1]] <- case("gigmom", c(ord, 0.7, chi, psi, lam), gigMom(ord, param = c(chi, psi, lam), about = 0.7), rel = 1e-9, abs = 1e-11)
  }
  cases[[length(cases) + 1]] <- case("gigvar2", c(0, chi, psi, lam), gigVar(chi, psi, lam), rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("gigskew", c(0, chi, psi, lam), gigSkew(chi, psi, lam), rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("gigkurt", c(0, chi, psi, lam), gigKurt(chi, psi, lam), rel = 1e-9, abs = 1e-12)
}
for (rep in 1:6) {
  psi <- runif(1, 0.3, 3); lam <- runif(1, 0.3, 3); chi <- runif(1, 0.3, 3); lm <- runif(1, -3, -1.2)
  for (ord in 1:3) {
    cases[[length(cases) + 1]] <- case("gigrawcase", c(ord, 0, psi, lam), gigRawMom(ord, 0, psi, lam), rel = 1e-10, abs = 1e-13)
    cases[[length(cases) + 1]] <- case("gigrawcase", c(ord, chi, 0, lm), gigRawMom(ord, chi, 0, lm), rel = 1e-10, abs = 1e-13)
  }
}
# "gigchpars" (from, to, p1, p2, index); "hyperbchpars" (from, to, delta, p3, p4, index); "ghypscale" (mean, sd, delta, alpha, beta, lambda, index 0 mu .. 3 beta);
# "ghypstand" (rho, zeta, lambda, 0, 0, 0, index); "ghypmombns" (order, delta, alpha, beta, lambda); "ghypmomabout" (order, about, mu, delta, alpha, beta, lambda)
for (from in 1:4) for (to in 1:4) for (rep in 1:4) {
  p <- runif(2, 0.3, 3)
  r <- gigChangePars(from, to, c(p, 0.5))
  for (j in 1:2) cases[[length(cases) + 1]] <- case("gigchpars", c(from, to, p, j - 1), r[j], rel = 1e-12, abs = 1e-14)
  delta <- runif(1, 0.5, 2); alpha <- runif(1, 1.2, 3); beta <- runif(1, -0.9, 0.9)
  q <- hyperbChangePars(2, from, c(0, delta, alpha, beta))
  r <- hyperbChangePars(from, to, q)
  for (j in 1:2) cases[[length(cases) + 1]] <- case("hyperbchpars", c(from, to, delta, q[3], q[4], j - 1), r[2 + j], rel = 1e-11, abs = 1e-13)
}
for (rep in 1:20) {
  mu <- rnorm(1); delta <- runif(1, 0.3, 3); alpha <- runif(1, 0.8, 4); beta <- runif(1, -0.8, 0.8) * alpha; lam <- runif(1, -2, 3)
  r <- ghypScale(2.5, 1.7, param = c(mu, delta, alpha, beta, lam))
  for (j in 1:4) cases[[length(cases) + 1]] <- case("ghypscale", c(2.5, 1.7, delta, alpha, beta, lam, j - 1), r[j], rel = 1e-9, abs = 1e-11)
  rho <- runif(1, -0.9, 0.9); zeta <- runif(1, 0.3, 4)
  r <- ghypStandPars(rho, zeta, lam)
  for (j in 1:4) cases[[length(cases) + 1]] <- case("ghypstand", c(rho, zeta, lam, 0, 0, 0, j - 1), r[j], rel = 1e-10, abs = 1e-12)
  for (ord in 1:4) {
    cases[[length(cases) + 1]] <- case("ghypmombns", c(ord, delta, alpha, beta, lam), ghypMomBNS(ord, param = c(mu, delta, alpha, beta, lam)), rel = 1e-9, abs = 1e-12)
    cases[[length(cases) + 1]] <- case("ghypmomabout", c(ord, 0.4, mu, delta, alpha, beta, lam), ghypMom(ord, param = c(mu, delta, alpha, beta, lam), about = 0.4), rel = 1e-9, abs = 1e-12)
  }
}
# "pghypT" (q, mu, delta, alpha, beta, lambda, lower 0/1); "qghypF" (p, mu, delta, alpha, beta, lambda, lower 0/1, method 0 spline / 1 integrate);
# "ghypmode" (mu, delta, alpha, beta, lambda); "ghyprange" (tol, index 0 lower / 1 upper, mu, delta, alpha, beta, lambda); "gigrange" (tol, index, chi, psi, lambda)
set.seed(20262103)
for (rep in 1:14) {
  mu <- rnorm(1); delta <- runif(1, 0.3, 3); alpha <- runif(1, 0.8, 4); beta <- runif(1, -0.8, 0.8) * alpha; lam <- runif(1, -2, 2.5)
  pr <- c(mu, delta, alpha, beta, lam)
  for (x in mu + c(-5, -1, 0.3, 2, 6) * delta) for (lo in c(TRUE, FALSE))
    cases[[length(cases) + 1]] <- case("pghypT", c(x, pr, as.numeric(lo)), pghyp(x, param = pr, lower.tail = lo), rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("ghypmode", pr, ghypMode(param = pr), rel = 1e-9, abs = 1e-12)
  for (tl in c(1e-5, 1e-3)) {
    rg <- ghypCalcRange(param = pr, tol = tl)
    for (j in 1:2) cases[[length(cases) + 1]] <- case("ghyprange", c(tl, j - 1, pr), rg[j], rel = 1e-9, abs = 1e-12)
  }
  if (rep <= 4) for (pp in c(0.001, 0.3, 0.8, 0.9995)) for (lo in c(TRUE, FALSE)) {
    v <- tryCatch(qghyp(pp, param = pr, lower.tail = lo), error = function(e) NA_real_)
    if (is.finite(v)) cases[[length(cases) + 1]] <- case("qghypF", c(pp, pr, as.numeric(lo), 0), v, rel = 1e-9, abs = 1e-12)
  }
  if (rep <= 6) for (pp in c(0.001, 0.3, 0.9995)) {
    v <- tryCatch(qghyp(pp, param = pr, method = "integrate"), error = function(e) NA_real_)
    if (is.finite(v)) cases[[length(cases) + 1]] <- case("qghypF", c(pp, pr, 1, 1), v, rel = 1e-9, abs = 1e-12)
  }
  chi <- runif(1, 0.3, 3); psi <- runif(1, 0.3, 3); lg <- runif(1, -2, 2.5)
  for (tl in c(1e-5, 1e-7)) {
    rg <- gigCalcRange(chi, psi, lg, tol = tl)
    for (j in 1:2) cases[[length(cases) + 1]] <- case("gigrange", c(tl, j - 1, chi, psi, lg), rg[j], rel = 1e-9, abs = 1e-12)
  }
}
# "famrange" (tol, index 0 lower / 1 upper, family 0 hyperb / 1 nig, mu, delta, alpha, beta)
for (rep in 1:10) {
  mu <- rnorm(1); delta <- runif(1, 0.3, 3); alpha <- runif(1, 0.8, 4); beta <- runif(1, -0.8, 0.8) * alpha
  pr <- c(mu, delta, alpha, beta)
  for (tl in c(1e-5, 1e-3, 1e-8)) {
    rh <- hyperbCalcRange(param = pr, tol = tl); rn <- nigCalcRange(param = pr, tol = tl)
    for (j in 1:2) {
      cases[[length(cases) + 1]] <- case("famrange", c(tl, j - 1, 0, pr), rh[j], rel = 1e-9, abs = 1e-12)
      cases[[length(cases) + 1]] <- case("famrange", c(tl, j - 1, 1, pr), rn[j], rel = 1e-9, abs = 1e-12)
    }
  }
}
# "qopt" (family 0 hyperb / 1 nig / 2 ghyp, p, mu, delta, alpha, beta, lambda, lower 0/1, method 0 spline / 1 integrate, nInterpol, uniTol, subdivisions)
set.seed(20262104)
for (rep in 1:12) {
  mu <- rnorm(1); delta <- runif(1, 0.3, 3); alpha <- runif(1, 0.8, 4); beta <- runif(1, -0.8, 0.8) * alpha; lam <- runif(1, -2, 2.5)
  fam <- (rep - 1) %% 3
  pr <- c(mu, delta, alpha, beta)
  lm <- c(1, -0.5, lam)[fam + 1]
  lo <- c(TRUE, FALSE)[sample(1:2, 1)]; me <- (rep %/% 3) %% 2
  ni <- c(201, 501, 1001)[sample(1:3, 1)]; ut <- c(1e-3, .Machine$double.eps^0.25, 1e-6)[sample(1:3, 1)]; sb <- c(100, 200)[sample(1:2, 1)]
  for (pp in c(0.02, 0.4, 0.97)) {
    mth <- c("spline", "integrate")[me + 1]
    v <- tryCatch(suppressWarnings(switch(fam + 1,
      qhyperb(pp, param = pr, lower.tail = lo, method = mth, nInterpol = ni, uniTol = ut, subdivisions = sb),
      qnig(pp, param = pr, lower.tail = lo, method = mth, nInterpol = ni, uniTol = ut, subdivisions = sb),
      qghyp(pp, param = c(pr, lam), lower.tail = lo, method = mth, nInterpol = ni, uniTol = ut, subdivisions = sb))), error = function(e) NA_real_)
    if (is.finite(v)) cases[[length(cases) + 1]] <- case("qopt", c(fam, pp, pr, lm, as.numeric(lo), me, ni, ut, sb), v, rel = 1e-9, abs = 1e-12)
  }
}
# the families' statistics: "famstat" (family 0 hyperb / 1 nig, what 0 mean 1 var 2 skew 3 kurt 4 mode, mu, delta, alpha, beta)
for (rep in 1:20) {
  mu <- rnorm(1); delta <- runif(1, 0.3, 3); alpha <- runif(1, 0.8, 4); beta <- runif(1, -0.8, 0.8) * alpha
  pr <- c(mu, delta, alpha, beta)
  hv <- c(hyperbMean(param = pr), hyperbVar(param = pr), hyperbSkew(param = pr), hyperbKurt(param = pr), hyperbMode(param = pr))
  nv <- c(nigMean(param = pr), nigVar(param = pr), nigSkew(param = pr), nigKurt(param = pr), nigMode(param = pr))
  for (w in 1:5) {
    cases[[length(cases) + 1]] <- case("famstat", c(0, w - 1, pr), hv[w], rel = 1e-9, abs = 1e-12)
    cases[[length(cases) + 1]] <- case("famstat", c(1, w - 1, pr), nv[w], rel = 1e-9, abs = 1e-12)
  }
  rho <- runif(1, -0.8, 0.8); zeta <- runif(1, 0.4, 3)
  for (x in c(-1.2, 0, 0.7)) cases[[length(cases) + 1]] <- case("dshyperb", c(x, rho, zeta), dshyperb(x, rho, zeta), rel = 1e-9, abs = 1e-13)
}
# "rnig" and "rhyperb" (seed, n, i, mu, delta, alpha, beta), "rgigx" (seed, n, i, chi, psi, lambda)
for (rep in 1:8) {
  mu <- rnorm(1); delta <- runif(1, 0.3, 3); alpha <- runif(1, 0.8, 4); beta <- runif(1, -0.8, 0.8) * alpha
  chi <- runif(1, 0.3, 3); psi <- runif(1, 0.3, 3); lg <- c(runif(1, -2, 0.9), 1, runif(1, 1.1, 3))[sample(1:3, 1)]
  sd0 <- sample(1:100000, 1); n <- 5
  set.seed(sd0); v <- rnig(n, param = c(mu, delta, alpha, beta))
  for (i in seq_len(n)) cases[[length(cases) + 1]] <- case("rnig", c(sd0, n, i - 1, mu, delta, alpha, beta), v[i], rel = 1e-9, abs = 1e-12)
  set.seed(sd0); v <- rhyperb(n, param = c(mu, delta, alpha, beta))
  for (i in seq_len(n)) cases[[length(cases) + 1]] <- case("rhyperb", c(sd0, n, i - 1, mu, delta, alpha, beta), v[i], rel = 1e-9, abs = 1e-12)
  set.seed(sd0); v <- rgig(n, chi, psi, lg)
  for (i in seq_len(n)) cases[[length(cases) + 1]] <- case("rgigx", c(sd0, n, i - 1, chi, psi, lg), v[i], rel = 1e-9, abs = 1e-12)
}
# "rlam" (what 0 RLambda, 1 SLambda, 2 MLambda, 3 WLambda1, 4 WLambda2, 5 WLambda3, 6 WLambda4, zeta, lambda); "gamlam" (1 or 2, pi, zeta, lambda); "dgigs" and "ddgig"
# (x, chi, psi, lambda); "ddfam" (family 0 hyperb / 1 nig, x, mu, delta, alpha, beta)
for (rep in 1:20) {
  zeta <- runif(1, 0.3, 6); lam <- runif(1, -2, 3); pi_ <- runif(1, -1.5, 1.5)
  v <- c(RLambda(zeta, lam), SLambda(zeta, lam), MLambda(zeta, lam), WLambda1(zeta, lam), WLambda2(zeta, lam), WLambda3(zeta, lam), WLambda4(zeta, lam))
  for (w in 0:6) cases[[length(cases) + 1]] <- case("rlam", c(w, zeta, lam), v[w + 1], rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("gamlam", c(1, pi_, zeta, lam), gammaLambda1(pi_, zeta, lam), rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("gamlam", c(2, pi_, zeta, lam), gammaLambda2(pi_, zeta, lam), rel = 1e-9, abs = 1e-12)
  chi <- runif(1, 0.3, 3); psi <- runif(1, 0.3, 3)
  for (x in c(0.2, 0.9, 3)) {
    cases[[length(cases) + 1]] <- case("dgigs", c(x, chi, psi, lam), dgigScaled(x, chi, psi, lam), rel = 1e-9, abs = 1e-13)
    cases[[length(cases) + 1]] <- case("ddgig", c(x, chi, psi, lam), ddgig(x, chi, psi, lam), rel = 1e-9, abs = 1e-13)
  }
  mu <- rnorm(1); delta <- runif(1, 0.3, 3); alpha <- runif(1, 0.8, 4); beta <- runif(1, -0.8, 0.8) * alpha
  for (x in mu + c(-2, 0.3, 1.5)) {
    cases[[length(cases) + 1]] <- case("ddfam", c(0, x, mu, delta, alpha, beta), ddhyperb(x, param = c(mu, delta, alpha, beta)), rel = 1e-9, abs = 1e-13)
    cases[[length(cases) + 1]] <- case("ddfam", c(1, x, mu, delta, alpha, beta), ddnig(x, param = c(mu, delta, alpha, beta)), rel = 1e-9, abs = 1e-13)
  }
}
emit("ghyp2", c("GeneralizedHyperbolic", "DistributionUtils"), list(cases))
