# MASS fitdistr with a user-supplied densfun function (start, lower / upper, forced methods): the optim call MASS builds for a function, no parscale, no gradient.
# Tolerance 1e-4 for id 3 (a fit whose optimiser path is sensitive to one-ulp exp/log differences, measured by mass_probe.R), 1e-8 for the rest
#   "fdu" (id 0 Gumbel 1 inverse Gaussian (densfun with a log argument) 2 Rayleigh 3 location-scale t (log argument), bounded, method 0 auto 1 BFGS 2 NM 3 LBFGSB, np, start[3], lower[3], upper[3], which, x[n])
#   which 0 .. np - 1 estimates, np .. 2 np - 1 standard errors, 2 np the log-likelihood, 50 the position-weighted sum of vcov, 51 vcov[2], 100 n
suppressMessages(library(MASS))
cases <- list()
set.seed(20262611)
dgum <- function(x, mu, beta) { z <- (x - mu) / beta; exp(-(z + exp(-z))) / beta }
dig <- function(x, mu, lambda, log = FALSE) { l <- 0.5 * log(lambda / (2 * pi * x^3)) - lambda * (x - mu)^2 / (2 * mu^2 * x); if (log) l else exp(l) }
dray <- function(x, s) x / s^2 * exp(-x^2 / (2 * s^2))
dtls <- function(x, m, s, df, log = FALSE) { l <- dt((x - m) / s, df, log = TRUE) - log(s); if (log) l else exp(l) }
dens <- list(dgum, dig, dray, dtls)
np_of <- c(2, 2, 1, 3)
for (rep in 1:48) {
  id <- (rep - 1) %% 4; n <- sample(50:150, 1)
  x <- switch(id + 1, 2 - 1.5 * log(-log(runif(n))), rgamma(n, 4, 2), sqrt(-2 * 1.7^2 * log(runif(n))), 1 + 2 * rt(n, 3))
  np <- np_of[id + 1]
  st <- switch(id + 1, c(mu = 1.5, beta = 1.2), c(mu = 1.8, lambda = 5), c(s = 1.2), c(m = 0.5, s = 1.5, df = 5))
  scen <- (rep - 1) %/% 4 %% 4  # 0 default method, 1 bounded, 2 forced BFGS, 3 forced Nelder-Mead
  bounded <- 0; method <- 0; lo <- rep(-1e308, 3); up <- rep(1e308, 3)
  args <- list(x, dens[[id + 1]], as.list(st))
  if (scen == 1) {
    bounded <- 1; lo[1:np] <- c(-10, 0.01, 1)[seq_len(np)]
    if (id == 1) lo[1:2] <- c(0.01, 0.01)
    if (id == 2) lo[1] <- 0.01
    up[1:np] <- 60; args$lower <- lo[1:np]; args$upper <- up[1:np]
  }
  if (scen == 2) { method <- 1; args$method <- "BFGS" }
  if (scen == 3) { method <- 2; args$method <- "Nelder-Mead" }
  r <- tryCatch(suppressWarnings(do.call(fitdistr, args)), error = function(e) NULL)
  if (is.null(r)) next
  v <- c(r$estimate, r$sd, r$loglik); stf <- c(st, 0, 0, 0)[1:3]
  rel <- if (id == 3) 1e-4 else 1e-8
  head <- c(id, bounded, method, np, stf, lo, up)
  for (w in 0:(2 * np)) cases[[length(cases) + 1]] <- case("fdu", c(head, w, x), v[w + 1], rel = rel, abs = 1e-6)
  vc <- as.vector(r$vcov)
  cases[[length(cases) + 1]] <- case("fdu", c(head, 50, x), sum(seq_along(vc) * vc), rel = rel, abs = 1e-6)
  if (np >= 2) cases[[length(cases) + 1]] <- case("fdu", c(head, 51, x), vc[2], rel = rel, abs = 1e-6)
  cases[[length(cases) + 1]] <- case("fdu", c(head, 100, x), r$n, rel = 0, abs = 0)
}
emit("mass_fdu", "MASS", list(cases))
