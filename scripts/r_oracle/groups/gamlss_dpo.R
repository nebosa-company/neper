# gamlss.dist DPO (double Poisson). Args: (fn, mu, sigma, x): fn 0 dDPO, 1 pDPO, 2 qDPO (x is then the probability).
suppressMessages(library(gamlss.dist))
cases <- list()
add <- function(fn, args, want, rel, abs) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261260)
for (rep in 1:40) {
  mu <- runif(1, 0.5, 15); sg <- runif(1, 0.4, 3); x <- rpois(1, mu)
  add("dp", c(0, mu, sg, x), dDPO(x, mu = mu, sigma = sg), 1e-7, 1e-12)
  add("dp", c(1, mu, sg, x), pDPO(x, mu = mu, sigma = sg), 1e-7, 1e-12)
  pr <- runif(1, 0.02, 0.98)
  add("dp", c(2, mu, sg, pr), qDPO(pr, mu = mu, sigma = sg), 0, 0)
}
# DBI (double binomial): (fn, mu, sigma, x, bd) with fn 3 dDBI, 4 pDBI, 5 qDBI
for (rep in 1:40) {
  mu <- runif(1, 0.1, 0.9); sg <- runif(1, 0.4, 3); bd <- sample(3:30, 1); x <- rbinom(1, bd, mu)
  add("dp", c(3, mu, sg, x, bd), dDBI(x, mu = mu, sigma = sg, bd = bd), 1e-9, 1e-14)
  add("dp", c(4, mu, sg, x, bd), pDBI(x, mu = mu, sigma = sg, bd = bd), 1e-9, 1e-14)
  pr <- runif(1, 0.02, 0.98)
  add("dp", c(5, mu, sg, pr, bd), qDBI(pr, mu = mu, sigma = sg, bd = bd), 0, 0)
}
# GAF (fn 6 d, 7 p, 8 q; mu, sigma, nu, x) and ZISICHEL (fn 9; mu, sigma, nu, tau, x)
for (rep in 1:40) {
  mu <- runif(1, 0.5, 6); sg <- runif(1, 0.3, 1.5); nu <- runif(1, -1, 3); x <- rgamma(1, 2, 1)
  add("dp", c(6, mu, sg, x, nu), dGAF(x, mu = mu, sigma = sg, nu = nu), 1e-9, 1e-14)
  add("dp", c(7, mu, sg, x, nu), pGAF(x, mu = mu, sigma = sg, nu = nu), 1e-9, 1e-14)
  pr <- runif(1, 0.02, 0.98)
  add("dp", c(8, mu, sg, pr, nu), qGAF(pr, mu = mu, sigma = sg, nu = nu), 1e-7, 1e-12)
  tau <- runif(1, 0.05, 0.6); nu2 <- runif(1, -1.5, 1); xi <- rpois(1, mu)
  add("dp", c(9, mu, sg, xi, nu2, tau), dZISICHEL(xi, mu = mu, sigma = sg, nu = nu2, tau = tau), 1e-7, 1e-12)
}
emit("gamlss_dpo", "gamlss.dist", list(cases))
