# gamlss.dist family objects' mean and variance of the families gamlss_mom does not carry: "fm3" args (fam, which 0 mean 1 variance, mu, sigma, nu, tau, bd) with fam 0 BB, 1 BEINF, 2 BNB, 3 GAF, 4 GB2, 5 GIG,
# 6 GT, 7 JSUo, 8 NBF, 9 NET, 10 NOF, 11 PARETO2o, 12 PE2, 13 PIG, 14 SHASHo, 15 SN2, 16 SST, 17 ST2, 18 ST3, 19 ST4, 20 ST5, 21 WARING, 22 ZABNB, 23 ZAPIG, 24 ZASICHEL, 25 ZAZIPF, 26 ZIBNB, 27 ZIPF,
# 28 ZIPIG, 29 ZISICHEL; the cases the package answers with Inf or NaN are left out
suppressMessages(library(gamlss.dist))
cases <- list()
fams <- list(BB, BEINF, BNB, GAF, GB2, GIG, GT, JSUo, NBF, NET, NOF, PARETO2o, PE2, PIG, SHASHo, SN2, SST, ST2, ST3, ST4, ST5, WARING, ZABNB, ZAPIG, ZASICHEL, ZAZIPF, ZIBNB, ZIPF, ZIPIG, ZISICHEL)
U <- function(a, b) runif(1, a, b)
set.seed(20269303)
for (f in 0:29) for (rep in 1:8) {
  mu <- U(0.5, 4); sg <- U(0.3, 1.5); nu <- 1; tau <- 1; bd <- sample(5:15, 1)
  b01 <- U(0.2, 0.8); z <- U(0.05, 0.5)
  pr <- switch(f + 1,
    list(mu = b01, sigma = U(0.1, 1.5), bd = bd),
    list(mu = U(0.3, 0.7), sigma = U(0.2, 0.6), nu = U(0.1, 0.5), tau = U(0.1, 0.5)),
    list(mu = mu, sigma = U(0.1, 0.8), nu = U(0.1, 0.9)),
    list(mu = mu, sigma = sg, nu = U(1, 3)),
    list(mu = mu, sigma = U(0.3, 1.5), nu = U(0.5, 3), tau = U(3, 6)),
    list(mu = mu, sigma = sg, nu = U(-1, 2)),
    list(mu = rnorm(1), sigma = sg, nu = U(3, 8), tau = U(1, 3)),
    list(mu = rnorm(1), sigma = U(0.5, 2), nu = U(-1, 1), tau = U(0.5, 2)),
    list(mu = mu, sigma = U(0.1, 1), nu = U(1, 3)),
    { n1 <- U(0.5, 2); list(mu = rnorm(1), sigma = U(0.3, 2), nu = n1, tau = n1 + U(1.5, 4)) },
    list(mu = mu, sigma = sg, nu = U(0, 2)),
    list(mu = mu, sigma = U(2.5, 5)),
    list(mu = rnorm(1), sigma = U(0.5, 2), nu = U(1, 3)),
    list(mu = mu, sigma = U(0.2, 1)),
    list(mu = rnorm(1), sigma = U(0.5, 2), nu = rnorm(1), tau = U(0.5, 2)),
    list(mu = rnorm(1), sigma = U(0.3, 2), nu = U(0.5, 2)),
    list(mu = rnorm(1), sigma = U(0.3, 2), nu = U(0.5, 2), tau = U(3, 10)),
    list(mu = rnorm(1), sigma = U(0.3, 2), nu = rnorm(1), tau = U(3, 8)),
    list(mu = rnorm(1), sigma = U(0.3, 2), nu = U(0.5, 2), tau = U(3, 10)),
    list(mu = rnorm(1), sigma = U(0.3, 2), nu = U(3, 8), tau = U(3, 8)),
    list(mu = rnorm(1), sigma = U(0.3, 2), nu = rnorm(1), tau = U(0.3, 1)),
    list(mu = U(0.5, 3), sigma = U(0.1, 0.8)),
    list(mu = mu, sigma = U(0.1, 0.8), nu = U(0.1, 0.9), tau = z),
    list(mu = mu, sigma = U(0.3, 1), nu = z),
    list(mu = mu, sigma = U(0.3, 1), nu = U(-1, 1), tau = z),
    list(mu = U(2.5, 5), sigma = z),
    list(mu = mu, sigma = U(0.1, 0.8), nu = U(0.1, 0.9), tau = z),
    list(mu = U(2.5, 5)),
    list(mu = mu, sigma = sg, nu = z),
    list(mu = mu, sigma = U(0.3, 1), nu = U(-1, 1), tau = z))
  o <- fams[[f + 1]]()
  all <- c(mu = 0, sigma = 0, nu = 0, tau = 0, bd = 0)
  for (nm in names(pr)) all[nm] <- pr[[nm]]
  for (w in 0:1) {
    fn <- if (w == 0) o$mean else o$variance
    v <- suppressWarnings(tryCatch(do.call(fn, pr[names(pr) %in% names(formals(fn))]), error = function(e) NaN))
    if (length(v) == 1 && is.finite(v)) cases[[length(cases) + 1]] <- case("fm3", c(f, w, all["mu"], all["sigma"], all["nu"], all["tau"], all["bd"]), v, rel = 1e-8, abs = 1e-11)
  }
}
emit("gamlss_mom2", "gamlss.dist", list(cases))
