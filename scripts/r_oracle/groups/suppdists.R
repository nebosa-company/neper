# SuppDists: inverse Gaussian d/p/q, Kendall d/p, Spearman d/p (exact, small N), Johnson SN, SL, SB, SU d/p/q.
#   args: (kind, a, b, c, d, e, x)  see each fn
#   "ig_d" "ig_p" "ig_q": (nu, lambda, x)   "ken_d" "ken_p": (N, tau)   "sp_d" "sp_p": (N, rho)   "jo_d" "jo_p" "jo_q": (type 0 SN 1 SL 2 SB 3 SU, gamma, delta, xi, lambda, x)
suppressMessages(library(SuppDists))
cases <- list()
add <- function(fn, args, want, tol = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = tol, abs = 1e-12)
set.seed(20261116)
for (rep in 1:25) {
  nu <- round(runif(1, 0.5, 4), 2); la <- round(runif(1, 0.5, 6), 2); x <- round(runif(1, 0.2, 4), 2); pr <- round(runif(1, 0.05, 0.95), 3)
  add("ig_d", c(nu, la, x), dinvGauss(x, nu, la)); add("ig_p", c(nu, la, x), pinvGauss(x, nu, la)); add("ig_q", c(nu, la, pr), qinvGauss(pr, nu, la), 1e-7)
}
for (N in 3:9) for (tau in seq(-1, 1, by = 0.13)) { add("ken_d", c(N, tau), dKendall(tau, N)); add("ken_p", c(N, tau), pKendall(tau, N)) }
for (N in 3:9) for (rep in 1:12) { rho <- cor(1:N, sample(N)); if (rho < 1) { add("sp_d", c(N, rho), dSpearman(rho, N)); add("sp_p", c(N, rho), pSpearman(rho, N)) } }
tn <- c("SN", "SL", "SB", "SU")
for (rep in 1:20) {
  ty <- sample(0:3, 1); g <- round(rnorm(1), 2); de <- round(runif(1, 0.6, 2), 2); xi <- round(runif(1, -1, 1), 2); la <- if (ty == 1) 1 else round(runif(1, 0.8, 3), 2)
  pr <- list(gamma = g, delta = de, xi = xi, lambda = la, type = tn[ty + 1])
  x <- if (ty == 2) xi + la * runif(1, 0.05, 0.95) else xi + la * runif(1, 0.1, 2); p <- round(runif(1, 0.05, 0.95), 3)
  a <- c(ty, g, de, xi, la)
  add("jo_d", c(a, x), dJohnson(x, pr)); add("jo_p", c(a, x), pJohnson(x, pr)); add("jo_q", c(a, p), qJohnson(p, pr), 1e-8)
}
# ghyper: "gh_d" "gh_p" "gh_q" args (a, k, N, x)
for (rep in 1:10) { N <- sample(10:40, 1); a <- sample(2:(N - 2), 1); k <- sample(2:(N - 2), 1); for (xx in seq(max(0, k + a - N), min(a, k))) { add("gh_d", c(a, k, N, xx), dghyper(xx, a, k, N)); add("gh_p", c(a, k, N, xx), pghyper(xx, a, k, N)) }
  for (pr in c(0.1, 0.5, 0.9)) add("gh_q", c(a, k, N, pr), qghyper(pr, a, k, N)) }
# Pearson correlation: "pc_d" "pc_p" "pc_q": args (rho, N, x or p)
for (rep in 1:40) {
  N <- sample(5:60, 1); rho <- round(runif(1, -0.9, 0.9), 2); r <- round(runif(1, -0.95, 0.95), 3); pr <- round(runif(1, 0.05, 0.95), 3)
  add("pc_d", c(rho, N, r), dPearson(r, N, rho)); add("pc_p", c(rho, N, r), pPearson(r, N, rho), 1e-7); add("pc_q", c(rho, N, pr), qPearson(pr, N, rho), 1e-6)
}
# Kruskal-Wallis (ns 0) and normal scores (ns 1): "kw_p" "kw_u" "kw_q" "kw_d", args (ns, c, N, U, x or p)
for (rep in 1:40) {
  ns <- rep %% 2; cc <- sample(3:6, 1); ni <- sample(4:15, cc, TRUE); N <- sum(ni); U <- sum(1 / ni)
  h <- round(runif(1, 0.3, 9), 2); pr <- round(runif(1, 0.05, 0.95), 3)
  P <- if (ns == 0) pKruskalWallis else pNormScore; Q <- if (ns == 0) qKruskalWallis else qNormScore; D <- if (ns == 0) dKruskalWallis else dNormScore
  add("kw_p", c(ns, cc, N, U, h), P(h, cc, N, U), 1e-8); add("kw_u", c(ns, cc, N, U, h), P(h, cc, N, U, lower.tail = FALSE), 1e-8)
  add("kw_q", c(ns, cc, N, U, pr), Q(pr, cc, N, U), 1e-8); add("kw_d", c(ns, cc, N, U, h), D(h, cc, N, U), 1e-6)
}
# maximum F ratio: "mf_p" "mf_u" "mf_d" args (df, k, x), "mf_q" args (df, k, p)
for (rep in 1:40) {
  df <- sample(c(2, 3, 5, 8, 16, 30, 64), 1); k <- sample(3:12, 1); x <- round(runif(1, 1.1, 8), 3); pr <- round(runif(1, 0.05, 0.95), 3)
  add("mf_p", c(df, k, x), pmaxFratio(x, df, k), 1e-6); add("mf_u", c(df, k, x), pmaxFratio(x, df, k, lower.tail = FALSE), 1e-6)
  add("mf_d", c(df, k, x), dmaxFratio(x, df, k), 1e-6); add("mf_q", c(df, k, pr), qmaxFratio(pr, df, k), 1e-5)
}
# Friedman: "fr_p" "fr_u" "fr_d" args (r, N, x), "fr_q" args (r, N, p)
fr_cases <- list(c(3, 4), c(3, 7), c(3, 12), c(4, 5), c(4, 9), c(5, 4), c(5, 7), c(6, 5), c(4, 20), c(3, 40))
for (cs in fr_cases) for (rep in 1:5) {
  r <- cs[1]; N <- cs[2]; mx <- N * (r - 1); x <- if (rep <= 3) round(runif(1, 0.2, mx * 0.8), 2) else (2 * sample(1:(N * r * (r + 1) %/% 12), 1)) * 12 / (N * r * (r + 1)); pr <- round(runif(1, 0.05, 0.95), 3)
  v <- tryCatch(pFriedman(x, r, N), error = function(e) NA); if (is.na(v)) next
  add("fr_p", c(r, N, x), v, 1e-8); add("fr_u", c(r, N, x), pFriedman(x, r, N, lower.tail = FALSE), 1e-8)
  add("fr_d", c(r, N, x), dFriedman(x, r, N), 1e-8); add("fr_q", c(r, N, pr), qFriedman(pr, r, N), 1e-8)
}
# the max F ratio summary is rounded to 2 digits by makeStatList, hence its tolerance
# moments: fn "mo_<dist>", args (parameters..., what) what 0 mean, 1 median, 2 mode, 3 variance, 4 third, 5 fourth central moment
mom_add <- function(fn, a, s, tol = 1e-8) {
  v <- c(s$Mean, s$Median, s$Mode, s$Variance, s$ThirdCentralMoment, s$FourthCentralMoment)
  for (i in 1:6) if (is.finite(v[i])) add(fn, c(a, i - 1), v[i], tol)
}
for (rep in 1:12) { nu <- round(runif(1, 0.5, 4), 2); lam <- round(runif(1, 0.5, 6), 2); mom_add("mo_ig", c(nu, lam), sinvGauss(nu, lam), 1e-7) }
jtypes <- c("SN", "SL", "SU", "SB"); jk <- c(0, 1, 3, 2)
for (rep in 1:24) {
  ty <- (rep - 1) %% 4 + 1; g <- round(runif(1, -1.5, 1.5), 2); dl <- round(runif(1, 0.6, 2), 2); xi <- round(runif(1, -1, 1), 2); lm <- if (ty == 2) 1 else round(runif(1, 0.5, 3), 2)
  s <- tryCatch(sJohnson(list(gamma = g, delta = dl, xi = xi, lambda = lm, type = jtypes[ty])), error = function(e) NULL); if (is.null(s)) next
  mom_add("mo_jo", c(g, dl, xi, lm, jk[ty]), s, 1e-6)
}
for (rep in 1:10) { df <- sample(c(8, 16, 30), 1); k <- sample(c(3, 6, 9), 1); s <- smaxFratio(df, k); mom_add("mo_mf", c(df, k), s, 0.1) }
for (rep in 1:12) {
  ns <- rep %% 2; cc <- sample(3:6, 1); ni <- sample(4:15, cc, TRUE); N <- sum(ni); U <- sum(1 / ni)
  s <- if (ns == 0) sKruskalWallis(cc, N, U) else sNormScore(cc, N, U); mom_add("mo_kw", c(ns, cc, N, U), s, 1e-6)
}
for (cs in list(c(3, 4), c(3, 9), c(4, 5), c(5, 4), c(6, 5), c(4, 20))) { s <- sFriedman(cs[1], cs[2]); mom_add("mo_fr", c(cs[1], cs[2]), s, 1e-6) }
for (r in c(3, 5, 8, 11)) { s <- sSpearman(r); mom_add("mo_sp", c(r), s, 1e-9) }
for (cs in list(c(10, 5, 30), c(4, 9, 25), c(12, 12, 40), c(3, 20, 50), c(8, 3, 15), c(15, 7, 60), c(6, 6, 20), c(20, 10, 100))) { s <- sghyper(cs[1], cs[2], cs[3]); mom_add("mo_gh", cs, s, 1e-9) }
for (rep in 1:10) { N <- sample(5:50, 1); rho <- round(runif(1, -0.9, 0.9), 2); s <- sPearson(N, rho); mom_add("mo_pc", c(rho, N), s, 1e-6) }
# Kendall as the package answers (exact to N = 12, Edgeworth beyond): "kp_p" "kp_u" "kp_d" args (N, tau), "kp_q" args (N, p), "kp_m" args (N, what 0 var, 1 fourth)
for (N in c(5, 8, 12, 13, 15, 20, 40)) {
  for (tau in c(-0.6, -0.2, 0.05, 0.3, 0.7)) {
    add("kp_p", c(N, tau), pKendall(tau, N), 1e-9); add("kp_u", c(N, tau), pKendall(tau, N, lower.tail = FALSE), 1e-9); add("kp_d", c(N, tau), dKendall(tau, N), 1e-9)
  }
  for (pr in c(0.05, 0.25, 0.5, 0.9)) add("kp_q", c(N, pr), qKendall(pr, N), 1e-9)
  s <- sKendall(N); add("kp_m", c(N, 0), s$Variance, 1e-9); add("kp_m", c(N, 1), s$FourthCentralMoment, 1e-7)
}
# Spearman as the package answers (the exact Friedman distribution for 2 blocks to r = 11, Walsh's beta approximation beyond): "sq_p" "sq_u" "sq_d" args (r, rho), "sq_q" args (r, p)
for (r in c(4, 5, 8, 11, 12, 15, 20)) {
  for (rho in c(-0.7, -0.3, 0.05, 0.4, 0.8)) { add("sq_p", c(r, rho), pSpearman(rho, r), 1e-8); add("sq_u", c(r, rho), pSpearman(rho, r, lower.tail = FALSE), 1e-8); add("sq_d", c(r, rho), dSpearman(rho, r), 1e-8) }
  for (pr in c(0.05, 0.3, 0.5, 0.95)) add("sq_q", c(r, pr), qSpearman(pr, r), 1e-8)
}
# Johnson fits: "jf_q" args (x95, x79.4, x50, x20.6, x5, what 0 gamma 1 delta 2 xi 3 lambda 4 type), "jf_m" args (mean, variance, m3, m4, what)
jf_code <- c(SN = 0, SL = 1, SB = 2, SU = 3)
jf_pick <- function(f, w) switch(w + 1, f$gamma, f$delta, f$xi, f$lambda, jf_code[[f$type]])
jf_fit_cases <- list(list(0, 1, 0.1, 3.0), list(1, 2, 0.3, 3.3), list(0, 1, 1, 8))
for (pr in list(c(0.3, 1.2, 2, 3), c(-1, 1.5, 0, 2), c(0.5, 1, 1, 3), c(-2, 0.7, 4, 5), c(1.5, 2, -1.5, 3), c(-0.4, 2.5, -2, 1.5), c(0, 1, 0, 1))) {
  v <- qJohnson(ppoints(400), list(gamma = pr[1], delta = pr[2], xi = pr[3], lambda = pr[4], type = "SU"))
  for (typ in c("SU", "SB", "SL")) {
    vv <- if (typ == "SU") v else if (typ == "SB") qJohnson(ppoints(400), list(gamma = pr[1], delta = pr[2], xi = pr[3], lambda = pr[4], type = "SB")) else qJohnson(ppoints(400), list(gamma = pr[1], delta = pr[2], xi = pr[3], lambda = pr[4], type = "SL"))
    qq <- quantile(vv, probs = c(0.95, 0.794, 0.5, 0.206, 0.05), names = FALSE)
    f <- tryCatch(JohnsonFit(vv, moment = "quant"), error = function(e) NULL)
    if (is.null(f) || any(!is.finite(c(f$gamma, f$delta, f$xi, f$lambda)))) next
    for (w in 0:4) add("jf_q", c(qq, w), jf_pick(f, w), 1e-7)
  }
}
for (m in list(c(0, 1, 0.01, 3.02), c(2, 4, 3.5, 22), c(1, 2.25, 1, 5.5), c(0, 1, 0.4, 3.5), c(5, 9, 3, 25), c(0, 1, 0, 2.2), c(3, 1, -0.5, 3.6), c(0, 1, 0.8, 4.2), c(0, 1, -2, 12), c(10, 3, 0.8, 4.5))) {
  f <- tryCatch(JohnsonFit(m, moment = "use"), error = function(e) NULL)
  if (is.null(f) || any(!is.finite(c(f$gamma, f$delta, f$xi, f$lambda)))) next
  for (w in 0:4) add("jf_m", c(m, w), jf_pick(f, w), 1e-5)
}
# random variates after set.seed: "rv_ig" (seed, nu, lambda, i), "rv_jo" (seed, g, d, xi, lm, kind, i), "rv_mf" (seed, df, k, i), "rv_pc" (seed, N, rho, i), "rv_kd" (seed, N, i), "rv_gh" (seed, a, k, N, i), "rv_kw" (seed, ns, c, N, U, i)
rv_n <- 8
rv_add <- function(fn, seed, par, v, tol = 1e-9) for (i in seq_along(v)) if (is.finite(v[i])) add(fn, c(seed, par, i - 1), v[i], tol)
for (sd in c(11, 2024)) {
  for (pp in list(c(1.5, 2), c(0.7, 4.2))) { set.seed(sd); rv_add("rv_ig", sd, pp, rinvGauss(rv_n, pp[1], pp[2])) }
  jt <- c("SN", "SL", "SU", "SB"); jk <- c(0, 1, 3, 2)
  for (ty in 1:4) { g <- c(0.3, -0.5, 0.8, -0.2)[ty]; dl <- c(1.2, 0.9, 1.5, 1.1)[ty]; xi <- c(0.1, 0, -0.4, 0.5)[ty]; lm <- if (ty == 2) 1 else c(2, 1, 1.5, 3)[ty]
    set.seed(sd); rv_add("rv_jo", sd, c(g, dl, xi, lm, jk[ty]), rJohnson(rv_n, list(gamma = g, delta = dl, xi = xi, lambda = lm, type = jt[ty]))) }
  for (pp in list(c(10, 4), c(25, 6))) { set.seed(sd); rv_add("rv_mf", sd, pp, rmaxFratio(rv_n, pp[1], pp[2])) }
  for (pp in list(c(12, 0.4), c(30, -0.6))) { set.seed(sd); rv_add("rv_pc", sd, pp, rPearson(rv_n, pp[1], pp[2])) }
  for (nn in c(8, 11, 16)) { set.seed(sd); rv_add("rv_kd", sd, nn, rKendall(rv_n, nn)) }
  for (pp in list(c(10, 5, 30), c(4, 9, 25))) { set.seed(sd); rv_add("rv_gh", sd, pp, rghyper(rv_n, pp[1], pp[2], pp[3])) }
  set.seed(sd); rv_add("rv_kw", sd, c(0, 4, 40, 0.1), rKruskalWallis(rv_n, 4, 40, 0.1), 1e-8)
}
emit("suppdists", "SuppDists", list(cases))
