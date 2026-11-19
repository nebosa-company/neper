# MASS negative.binomial family terms (linkfun, linkinv, mu.eta, validmu, valideta, initialize for the log, sqrt and identity links), rnegbin under set.seed, and
# gamma.shape / gamma.dispersion with it.lim and eps.max.
#   "nblink"  (kind 0 linkfun 1 linkinv 2 mu.eta, link 0 log 1 sqrt 2 identity, theta, x)
#   "nbvalid" (kind 0 validmu 1 valideta 2 initialize mustart (position-weighted), link, n, v[n])
#   "rnb"     (seed, n, nmu, nth, mu[nmu], theta[nth], mode 0 sum 1 weighted sum)
#   "gsx"     (itlim, epsmax, mode 0 alpha 1 SE 2 gamma.dispersion, n, deviance, df.residual, y[n], fitted[n], prior.weights[n])
suppressMessages(library(MASS))
cases <- list()
set.seed(20262801)
links <- c("log", "sqrt", "identity")
for (rep in 1:90) {
  l <- (rep - 1) %% 3; th <- runif(1, 0.3, 12); f <- negative.binomial(th, link = links[l + 1])
  mu <- if (rep %% 7 == 0) 1e-12 else runif(1, 0.05, 20); eta <- if (l == 1) runif(1, -3, 5) else if (rep %% 5 == 0) -800 else runif(1, -6, 6)
  cases[[length(cases) + 1]] <- case("nblink", c(0, l, th, mu), f$linkfun(mu), rel = 1e-13, abs = 1e-14)
  cases[[length(cases) + 1]] <- case("nblink", c(1, l, th, eta), f$linkinv(eta), rel = 1e-13, abs = 0)
  cases[[length(cases) + 1]] <- case("nblink", c(2, l, th, eta), f$mu.eta(eta), rel = 1e-13, abs = 0)
}
for (rep in 1:60) {
  l <- (rep - 1) %% 3; f <- negative.binomial(2, link = links[l + 1]); n <- sample(3:12, 1)
  mu <- runif(n, 0.1, 5); if (rep %% 4 == 0) mu[sample(n, 1)] <- sample(c(0, -1), 1)
  eta <- rnorm(n); if (rep %% 3 == 0) eta[sample(n, 1)] <- sample(c(0, -2, Inf, NA), 1)
  y <- rpois(n, 2); if (rep %% 2 == 0) y[sample(n, 2)] <- 0
  cases[[length(cases) + 1]] <- case("nbvalid", c(0, l, n, mu), as.numeric(f$validmu(mu)), rel = 0, abs = 0)
  if (!anyNA(eta)) cases[[length(cases) + 1]] <- case("nbvalid", c(1, l, n, eta), as.numeric(f$valideta(eta)), rel = 0, abs = 0)
  ms <- local({ weights <- rep(1, n); nobs <- n; eval(f$initialize); mustart })
  cases[[length(cases) + 1]] <- case("nbvalid", c(2, l, n, y), sum(seq_len(n) * ms), rel = 1e-14, abs = 1e-14)
}
for (rep in 1:50) {
  n <- sample(c(1, 5, 20, 60), 1); nmu <- sample(c(1, 1, 3, n), 1); nth <- sample(c(1, 1, 2, n), 1)
  mu <- runif(nmu, 0.2, 40); th <- runif(nth, 0.4, 30); seed <- sample(1e6, 1)
  set.seed(seed); x <- rnegbin(n, mu, th)
  cases[[length(cases) + 1]] <- case("rnb", c(seed, n, nmu, nth, mu, th, 0), sum(x), rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("rnb", c(seed, n, nmu, nth, mu, th, 1), sum(seq_len(n) * x), rel = 0, abs = 0)
}
set.seed(20262802)
for (rep in 1:30) {
  n <- sample(30:100, 1); x <- runif(n); shape <- runif(1, 0.8, 8); mu <- exp(0.5 + 1.2 * x)
  y <- rgamma(n, shape = shape, rate = shape / mu); w <- if (rep %% 2 == 0) round(runif(n, 0.5, 3), 2) else rep(1, n)
  f <- tryCatch(suppressWarnings(glm(y ~ x, family = Gamma(link = "log"), weights = w)), error = function(e) NULL)
  if (is.null(f)) next
  itl <- c(1, 2, 3, 5, 10, 25)[rep %% 6 + 1]; em <- c(0.0001220703125, 1e-3, 1e-6, 1e-10, 0.1)[rep %% 5 + 1]
  g <- suppressWarnings(gamma.shape(f, it.lim = itl, eps.max = em))
  a <- c(itl, em)
  b <- c(n, f$deviance, f$df.residual, y, f$fitted.values, f$prior.weights)
  cases[[length(cases) + 1]] <- case("gsx", c(a, 0, b), g$alpha, rel = 1e-9, abs = 1e-10)
  cases[[length(cases) + 1]] <- case("gsx", c(a, 1, b), g$SE, rel = 1e-9, abs = 1e-10)
  cases[[length(cases) + 1]] <- case("gsx", c(a, 2, b), suppressWarnings(gamma.dispersion(f, it.lim = itl, eps.max = em)), rel = 1e-9, abs = 1e-10)
}
emit("mass_nbx", "MASS", list(cases))
