# ghypmisc: DistributionUtils::momIntegrated for ghyp and gig, and hyperbCvMTest of GeneralizedHyperbolic (e.algo.stat.ghypdist / ghypcvm).
# "momint": (family 0 ghyp / 1 gig, order, about, absolute 0/1, p0..p4: mu, delta, alpha, beta, lambda or chi, psi, lambda, 0, 0)
# "cvmp": (delta, alpha, beta, Wsq, what 0 p-value (numeric, 0 when the package answers text) / 1 text code 1 "> 0.25", 2 "0.25", 3 "< 0.01", 4 "0.01", 0 numeric / 2 warnings)
# "cvmw": (seed, n, mu, delta, alpha, beta): the statistic of hyperbCvMTest of set.seed(seed); rhyperb(n, mu, delta, alpha, beta) against the same parameters
suppressMessages(library(GeneralizedHyperbolic))
suppressMessages(library(DistributionUtils))
cases <- list()
set.seed(20262107)
for (rep in 1:15) {
  mu <- rnorm(1); delta <- runif(1, 0.3, 3); alpha <- runif(1, 0.8, 4); beta <- runif(1, -0.8, 0.8) * alpha; lam <- runif(1, -2, 2.5)
  for (ord in 1:4) for (ab in 0:1) {
    about <- c(0, 0.5)[sample(1:2, 1)]
    v <- tryCatch(momIntegrated("ghyp", param = c(mu, delta, alpha, beta, lam), order = ord, about = about, absolute = ab == 1), error = function(e) NA_real_)
    if (is.finite(v)) cases[[length(cases) + 1]] <- case("momint", c(0, ord, about, ab, mu, delta, alpha, beta, lam), v, rel = 1e-8, abs = 1e-10)
  }
  chi <- runif(1, 0.3, 3); psi <- runif(1, 0.3, 3)
  for (ord in 1:3) {
    v <- tryCatch(momIntegrated("gig", param = c(chi, psi, lam), order = ord, about = 0), error = function(e) NA_real_)
    if (is.finite(v)) cases[[length(cases) + 1]] <- case("momint", c(1, ord, 0, 0, chi, psi, lam, 0, 0), v, rel = 1e-8, abs = 1e-10)
  }
}
for (rep in 1:120) {
  delta <- runif(1, 0.1, 6); alpha <- runif(1, 0.5, 4); beta <- runif(1, -0.95, 0.95) * alpha; w <- runif(1, 0.03, 0.45)
  r <- tryCatch(suppressWarnings(hyperbCvMTestPValue(delta, alpha, beta, w)), error = function(e) NULL)
  if (is.null(r)) next
  pv <- r$pValue
  code <- if (is.numeric(pv)) 0 else match(pv, c("> 0.25", "0.25", "< 0.01", "0.01"))
  cases[[length(cases) + 1]] <- case("cvmp", c(delta, alpha, beta, w, 0), if (is.numeric(pv)) pv else 0, rel = 0, abs = 1.5e-3)
  cases[[length(cases) + 1]] <- case("cvmp", c(delta, alpha, beta, w, 1), code, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("cvmp", c(delta, alpha, beta, w, 2), r$warn, rel = 0, abs = 0)
}
for (rep in 1:8) {
  n <- sample(30:90, 1); sd0 <- sample(1:100000, 1)
  mu <- rnorm(1); delta <- runif(1, 0.5, 2); alpha <- runif(1, 1, 3); beta <- runif(1, -0.6, 0.6) * alpha
  set.seed(sd0); x <- rhyperb(n, param = c(mu, delta, alpha, beta))
  res <- NULL
  invisible(capture.output(res <- hyperbCvMTest(x, param = c(mu, delta, alpha, beta))))
  cases[[length(cases) + 1]] <- case("cvmw", c(sd0, n, mu, delta, alpha, beta), res$statistic, rel = 1e-6, abs = 1e-9)
}
emit("ghypmisc", c("GeneralizedHyperbolic", "DistributionUtils"), list(cases))
