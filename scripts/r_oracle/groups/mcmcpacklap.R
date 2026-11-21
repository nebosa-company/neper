# MCMClogit and MCMCpoisson with marginal.likelihood = "Laplace" (optim BFGS, optimhess, solve): the logmarglike attribute.
#   "lapml": (kind 0 logit / 1 Poisson, n, k, y[n], X[n*k] row-major, beta.start[k], b0[k], B0[k*k])
suppressMessages(library(MCMCpack))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
rowm <- function(m) as.vector(t(m))
set.seed(20261126)
for (rep in 1:24) {
  n <- sample(30:80, 1); k <- sample(1:4, 1); X <- cbind(1, matrix(round(rnorm(n * (k - 1)), 3), n)); X <- X[, seq_len(k), drop = FALSE]
  tb <- round(rnorm(k, 0, 0.5), 2); pois <- rep %% 2 == 0
  y <- if (pois) rpois(n, exp(as.vector(X %*% tb) * 0.5)) else rbinom(n, 1, plogis(as.vector(X %*% tb)))
  beta0 <- round(rnorm(k, 0, 0.2), 2); b0 <- round(rnorm(k, 0, 0.5), 2); Bm <- round(crossprod(matrix(round(rnorm(k * k), 2), k)) * 0.5 + diag(k) * 0.5, 4)
  o <- tryCatch(suppressWarnings(do.call(if (pois) MCMCpoisson else MCMClogit, list(y ~ X - 1, burnin = 10, mcmc = 100, thin = 1, seed = 1, beta.start = beta0, b0 = b0, B0 = Bm, marginal.likelihood = "Laplace"))), error = function(e) NULL)
  if (is.null(o)) next
  add("lapml", c(if (pois) 1 else 0, n, k, y, rowm(X), beta0, b0, rowm(Bm)), attr(o, "logmarglike"))
}
# MCMClogit with user.prior.density (logpost.logit.userprior): kind 2 dnorm log, 3 dnorm density (logfun FALSE), 4 dcauchy log; scales in the first k of the B0 slot
set.seed(20261127)
for (rep in 1:24) {
  n <- sample(30:80, 1); k <- sample(1:4, 1); X <- cbind(1, matrix(round(rnorm(n * (k - 1)), 3), n)); X <- X[, seq_len(k), drop = FALSE]
  tb <- round(rnorm(k, 0, 0.5), 2); y <- rbinom(n, 1, plogis(as.vector(X %*% tb)))
  beta0 <- round(rnorm(k, 0, 0.2), 2); m <- round(rnorm(k, 0, 0.5), 2); s <- round(runif(k, 0.5, 3), 2)
  kind <- 2 + rep %% 3
  uf <- if (kind == 2) function(b, m, s) sum(dnorm(b, m, s, log = TRUE)) else if (kind == 3) function(b, m, s) prod(dnorm(b, m, s)) else function(b, m, s) sum(dcauchy(b, m, s, log = TRUE))
  o <- tryCatch(suppressWarnings(MCMClogit(y ~ X - 1, burnin = 10, mcmc = 100, thin = 1, seed = 1, beta.start = beta0, user.prior.density = uf, logfun = kind != 3, B0 = 1, m = m, s = s, marginal.likelihood = "Laplace")), error = function(e) NULL)
  if (is.null(o)) next
  add("lapml", c(kind, n, k, y, rowm(X), beta0, m, s, rep(0, k * k - k)), attr(o, "logmarglike"))
}
emit("mcmcpacklap", "MCMCpack", list(cases))
