# MCMCmetrop1R with V handed over (Scythe Mersenne stream); every case wants the position-weighted sum of the sample (row-major).
#   "mh": (seed, kind 0 log density -q1/2, 1 density exp(-q1/2) + 0.6 exp(-q2/2), npar, burnin, mcmc, thin, tune[npar], V[np*np], theta0[np], mu1[np], mu2[np], P[np*np]); q = (th - mu)' P (th - mu)
suppressMessages(library(MCMCpack))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
wsum <- function(m) sum(seq_along(m) * as.vector(t(m)))
rowm <- function(m) as.vector(t(m))
set.seed(20261125)
for (rep in 1:14) {
  np <- sample(1:4, 1); kind <- rep %% 2
  P <- round(crossprod(matrix(round(rnorm(np * np), 2), np)) + diag(np) * 0.5, 4); V <- round(crossprod(matrix(round(rnorm(np * np), 2), np)) + diag(np) * 0.3, 4)
  mu1 <- round(rnorm(np), 2); mu2 <- round(rnorm(np, 0, 2), 2); th0 <- round(rnorm(np), 2)
  tune <- if (rep %% 3 == 0) round(runif(np, 0.5, 1.5), 2) else rep(round(runif(1, 0.5, 1.5), 2), np)
  burn <- sample(5:40, 1); thin <- sample(1:3, 1); mc <- thin * sample(20:80, 1); seed <- sample(1:100000, 1)
  q <- function(th, mu) { d <- th - mu; sum(d * (P %*% d)) }
  fun <- if (kind == 0) function(th) -0.5 * q(th, mu1) else function(th) exp(-0.5 * q(th, mu1)) + 0.6 * exp(-0.5 * q(th, mu2))
  o <- capture.output(s <- MCMCmetrop1R(fun, th0, burnin = burn, mcmc = mc, thin = thin, tune = tune, seed = seed, logfun = (kind == 0), V = V))
  add("mh", c(seed, kind, np, burn, mc, thin, tune, rowm(V), th0, mu1, mu2, rowm(P)), wsum(as.matrix(s)))
  # "mhdef": the same arguments with V left out, so R finds it from optim's BFGS mode and Hessian (V in the arguments is ignored)
  s2 <- tryCatch({ capture.output(s2 <- suppressWarnings(MCMCmetrop1R(fun, th0, burnin = burn, mcmc = mc, thin = thin, tune = tune, seed = seed, logfun = (kind == 0)))); s2 }, error = function(e) NULL)
  if (!is.null(s2)) add("mhdef", c(seed, kind, np, burn, mc, thin, tune, rowm(V), th0, mu1, mu2, rowm(P)), wsum(as.matrix(s2)))
}
emit("mcmcpackmh", "MCMCpack", list(cases))
