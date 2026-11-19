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
emit("gamlss_mom", "gamlss.dist", list(cases))
