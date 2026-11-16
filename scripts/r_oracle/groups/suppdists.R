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
for (rep in 1:10) { N <- sample(5:50, 1); rho <- round(runif(1, -0.9, 0.9), 2); s <- sPearson(N, rho); mom_add("mo_pc", c(rho, N), s, 1e-6) }
emit("suppdists", "SuppDists", list(cases))
