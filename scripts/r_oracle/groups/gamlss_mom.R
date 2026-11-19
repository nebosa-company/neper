# gamlss.dist family objects' mean and variance: "fm" args (family, which 0 mean 1 variance, mu, sigma) families 0 NO 1 EXP 2 PO 3 GU 4 LO 5 IG 6 LOGNO 7 NBI 8 ZIP 9 WEI 10 BE 11 GA
suppressMessages(library(gamlss.dist))
cases <- list()
fams <- list(NO, EXP, PO, GU, LO, IG, LOGNO, NBI, ZIP, WEI, BE, GA)
set.seed(20261400)
for (f in 0:11) for (rep in 1:8) {
  mu <- if (f == 10) runif(1, 0.05, 0.95) else if (f == 8) runif(1, 0.5, 6) else if (f %in% c(0, 3, 4, 6)) rnorm(1, 0, 2) else runif(1, 0.3, 8)
  sg <- if (f == 10 || f == 8) runif(1, 0.05, 0.9) else runif(1, 0.3, 2.5)
  o <- fams[[f + 1]]()
  for (w in 0:1) { fn <- if (w == 0) o$mean else o$variance; v <- if (length(formals(fn)) == 1) fn(mu) else fn(mu, sg); if (is.finite(v)) cases[[length(cases) + 1]] <- case("fm", c(f, w, mu, sg), v, rel = 1e-12, abs = 1e-14) }
}
# the second set: "fm2" args (family, which, mu, sigma, nu, tau) with families 0 PARETO2 1 RG 2 TF 3 EGB2 4 PE 5 IGAMMA 6 NO2 7 BI (bd in nu) 8 GEOM 9 GEOMo 10 WEI2 11 WEI3 12 BEo 13 TF2 14 ZIP2 15 ZIBI (bd in nu)
# 16 NBII 17 ZINBI 18 ZAGA 19 PARETO1o 20 LG 21 YULE 22 GPO 23 JSU 24 exGAUS 25 SN1 26 DEL; the cases the package answers with Inf or NaN are left out
fams2 <- list(PARETO2, RG, TF, EGB2, PE, IGAMMA, NO2, BI, GEOM, GEOMo, WEI2, WEI3, BEo, TF2, ZIP2, ZIBI, NBII, ZINBI, ZAGA, PARETO1o, LG, YULE, GPO, JSU, exGAUS, SN1, DEL, ZAP, ZABI, ZANBI, ZALG, ST3C, SI, SICHEL, GG)
for (f in 0:34) for (rep in 1:8) {
  mu <- switch(f + 1, runif(1, 0.5, 5), rnorm(1), rnorm(1), rnorm(1), rnorm(1), runif(1, 0.5, 5), rnorm(1), runif(1, 0.1, 0.9), runif(1, 0.3, 6), runif(1, 0.1, 0.9), runif(1, 0.3, 4), runif(1, 0.3, 4), runif(1, 0.5, 4), rnorm(1), runif(1, 0.5, 5), runif(1, 0.1, 0.9), runif(1, 0.3, 5), runif(1, 0.3, 5), runif(1, 0.3, 5), runif(1, 0.5, 5), runif(1, 0.1, 0.9), runif(1, 0.1, 0.8), runif(1, 0.3, 5), rnorm(1), rnorm(1), rnorm(1), runif(1, 0.3, 5), runif(1, 0.5, 5), runif(1, 0.1, 0.9), runif(1, 0.3, 5), runif(1, 0.1, 0.9), rnorm(1), runif(1, 0.5, 5), runif(1, 0.5, 5), runif(1, 0.5, 5))
  sg <- switch(f + 1, runif(1, 0.1, 0.45), runif(1, 0.3, 2), runif(1, 0.3, 2), runif(1, 0.3, 2), runif(1, 0.3, 2), runif(1, 0.1, 0.6), runif(1, 0.3, 2), runif(1, 0.3, 2), runif(1, 0.3, 2), runif(1, 0.3, 2), runif(1, 0.5, 3), runif(1, 0.5, 3), runif(1, 0.5, 4), runif(1, 0.3, 2), runif(1, 0.05, 0.9), runif(1, 0.05, 0.9), runif(1, 0.3, 2), runif(1, 0.1, 2), runif(1, 0.1, 2), runif(1, 2.5, 6), runif(1, 0.3, 2), runif(1, 0.3, 2), runif(1, 0.1, 1), runif(1, 0.3, 2), runif(1, 0.3, 2), runif(1, 0.3, 2), runif(1, 0.1, 1.5), runif(1, 0.05, 0.9), runif(1, 0.05, 0.9), runif(1, 0.3, 2), runif(1, 0.05, 0.9), runif(1, 0.05, 0.9), runif(1, 0.05, 0.9), runif(1, 0.3, 2), runif(1, 0.05, 0.9), runif(1, 0.3, 2), runif(1, 0.3, 2), runif(1, 0.3, 2), runif(1, 0.2, 1.2))
  nu <- switch(f + 1, 1, 1, runif(1, 3, 9), runif(1, 0.5, 4), 1, 1, 1, sample(2:9, 1), 1, 1, 1, 1, 1, runif(1, 2.5, 8), 1, sample(2:9, 1), 1, runif(1, 0.05, 0.9), runif(1, 0.05, 0.9), 1, 1, 1, 1, rnorm(1), runif(1, 0.3, 3), runif(1, 0.3, 3), runif(1, 0.1, 0.9), 1, sample(2:9, 1), runif(1, 0.05, 0.9), 1, 1, sample(2:9, 1), runif(1, 0.05, 0.9), 1, runif(1, 0.3, 3), runif(1, -0.9, 2.5), runif(1, -0.9, 2.5), runif(1, -2, 3))
  tau <- if (f == 3) runif(1, 0.5, 4) else if (f == 31) runif(1, 2.5, 9) else 1
  o <- fams2[[f + 1]]()
  args <- list(mu = mu, sigma = sg, nu = nu, bd = nu, tau = tau)
  for (w in 0:1) { fn <- if (w == 0) o$mean else o$variance; fm <- names(formals(fn)); v <- do.call(fn, args[fm]); if (is.finite(v)) cases[[length(cases) + 1]] <- case("fm2", c(f, w, mu, sg, nu, tau), v, rel = 1e-9, abs = 1e-12) }
}
emit("gamlss_mom", "gamlss.dist", list(cases))
