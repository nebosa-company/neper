# MCMCpack samplers under an integer seed (the C++ uses its own Scythe Mersenne-Twister, so set.seed is not involved). Every sampler case passes (seed, ...) and wants
# a position-weighted sum of the posterior matrix (row-major), as in the mcmc group.
#   regress "reg" "regsig" "regml":  (seed, n, k, burnin, mcmc, thin, c0, d0, y[n], X[n*k] row-major, beta0[k], b0[k], B0[k*k])
#   logit/poisson "logit" "pois":    (seed, n, k, burnin, mcmc, thin, y[n], X[n*k], tune[k], beta0[k], b0[k], B0[k*k], V[k*k])
suppressMessages(library(MCMCpack))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
wsum <- function(m) sum(seq_along(m) * as.vector(t(m)))
rowm <- function(m) as.vector(t(m))
set.seed(20261121)
for (rep in 1:14) {
  n <- sample(15:40, 1); k <- sample(1:3, 1); X <- cbind(1, matrix(round(rnorm(n * (k - 1)), 3), n)); X <- X[, seq_len(k), drop = FALSE]
  y <- round(as.vector(X %*% round(rnorm(k), 2)) + rnorm(n), 3)
  beta0 <- round(rnorm(k), 2); b0 <- round(rnorm(k, 0, 0.5), 2); Bm <- crossprod(matrix(round(rnorm(k * k), 2), k)) + diag(k) * 0.3; Bm <- round(Bm, 4)
  burn <- sample(5:40, 1); thin <- sample(1:3, 1); mc <- thin * sample(20:60, 1); c0 <- round(runif(1, 0.5, 3), 2); d0 <- round(runif(1, 0.5, 3), 2); seed <- sample(1:100000, 1)
  o <- MCMCregress(y ~ X - 1, burnin = burn, mcmc = mc, thin = thin, seed = seed, beta.start = beta0, b0 = b0, B0 = Bm, c0 = c0, d0 = d0, marginal.likelihood = "Chib95")
  m <- as.matrix(o)
  a <- c(seed, n, k, burn, mc, thin, c0, d0, y, rowm(X), beta0, b0, rowm(Bm))
  add("reg", a, wsum(m)); add("regsig", a, wsum(m[, k + 1, drop = FALSE])); add("regml", a, attr(o, "logmarglike"))
}
for (rep in 1:14) {
  n <- sample(30:70, 1); k <- sample(1:3, 1); X <- cbind(1, matrix(round(rnorm(n * (k - 1)), 3), n)); X <- X[, seq_len(k), drop = FALSE]
  tb <- round(rnorm(k, 0, 0.5), 2); pois <- rep %% 2 == 0
  y <- if (pois) rpois(n, exp(as.vector(X %*% tb) * 0.5)) else rbinom(n, 1, plogis(as.vector(X %*% tb)))
  fit <- suppressWarnings(glm(y ~ X - 1, family = if (pois) poisson else binomial)); V <- vcov(fit)
  if (any(!is.finite(V)) || max(abs(coef(fit))) > 8) next
  beta0 <- round(rnorm(k, 0, 0.3), 2); tune <- round(runif(k, 0.7, 1.4), 2)
  flat <- rep %% 3 == 0
  b0 <- if (flat) rep(0, k) else round(rnorm(k, 0, 0.5), 2); Bm <- if (flat) matrix(0, k, k) else round(crossprod(matrix(round(rnorm(k * k), 2), k)) + diag(k) * 0.3, 4)
  burn <- sample(5:40, 1); thin <- sample(1:3, 1); mc <- thin * sample(20:60, 1); seed <- sample(1:100000, 1)
  args <- list(burnin = burn, mcmc = mc, thin = thin, tune = tune, seed = seed, beta.start = beta0, b0 = if (flat) 0 else b0, B0 = if (flat) 0 else Bm)
  o <- do.call(if (pois) MCMCpoisson else MCMClogit, c(list(y ~ X - 1), args))
  # V is vcov(glm), handed over at full precision because the sampler reads it
  a <- c(seed, n, k, burn, mc, thin, y, rowm(X), tune, beta0, b0, rowm(Bm), rowm(V))
  add(if (pois) "pois" else "logit", a, wsum(as.matrix(o)))
}
#   probit "probit" "probitml": (seed, n, k, burnin, mcmc, thin, y[n], X[n*k], beta0[k], b0[k], B0[k*k]); probitml only for k >= 2 (Scythe's lndmvn is NaN for 1 by 1)
for (rep in 1:14) {
  n <- sample(30:70, 1); k <- sample(1:3, 1); X <- cbind(1, matrix(round(rnorm(n * (k - 1)), 3), n)); X <- X[, seq_len(k), drop = FALSE]
  tb <- round(rnorm(k, 0, 0.7), 2); y <- rbinom(n, 1, pnorm(as.vector(X %*% tb)))
  beta0 <- round(rnorm(k, 0, 0.3), 2); b0 <- round(rnorm(k, 0, 0.5), 2); Bm <- round(crossprod(matrix(round(rnorm(k * k), 2), k)) + diag(k) * 0.3, 4)
  burn <- sample(5:30, 1); thin <- sample(1:3, 1); mc <- thin * sample(15:50, 1); seed <- sample(1:100000, 1)
  o <- MCMCprobit(y ~ X - 1, burnin = burn, mcmc = mc, thin = thin, seed = seed, beta.start = beta0, b0 = b0, B0 = Bm, marginal.likelihood = if (k >= 2) "Chib95" else "none")
  a <- c(seed, n, k, burn, mc, thin, y, rowm(X), beta0, b0, rowm(Bm))
  add("probit", a, wsum(as.matrix(o)))
  if (k >= 2) add("probitml", a, attr(o, "logmarglike"))
}
# rwish / riwish: (seed, p, v, S[p*p]) wanting wsum of the draw; rdir: (seed, n, alpha...) wanting wsum of the n by l matrix 
for (rep in 1:20) {
  p <- sample(1:4, 1); v <- p + sample(0:6, 1) + sample(c(0, 0.5), 1); S <- round(crossprod(matrix(round(rnorm(p * p), 2), p)) + diag(p) * 0.5, 4); seed <- sample(1:100000, 1)
  set.seed(seed); add("rwish", c(seed, p, v, rowm(S)), wsum(rwish(v, S)))
  set.seed(seed); add("riwish", c(seed, p, v, rowm(S)), wsum(riwish(v, S)))
  l <- sample(2:5, 1); nn <- sample(1:6, 1); al <- round(runif(l, 0.4, 5), 2)
  set.seed(seed); add("rdir", c(seed, nn, al), wsum(rdirichlet(nn, al)))
}
emit("mcmcpacksamp", "MCMCpack", list(cases))
