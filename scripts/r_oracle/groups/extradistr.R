# extraDistr: d, p and q of sixteen closed-form continuous distributions.
#   args: (dist, p1, p2, p3, v) fn "d" "p" "q"; dist 0 gumbel(mu, sigma) 1 frechet(lambda, mu, sigma) 2 kumar(a, b) 3 laplace(mu, sigma) 4 lomax(lambda, kappa)
#   5 pareto(a, b) 6 rayleigh(sigma) 7 triang(a, b, c) 8 gompertz(a, b) 9 power(alpha, beta) 10 invgamma(alpha, beta) 11 hnorm(sigma) 12 hcauchy(sigma)
#   13 fatigue(alpha, beta, mu) 14 wald(mu, lambda) (no q) 15 betapr(alpha, beta, sigma)
suppressMessages(library(extraDistr))
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261130)
names0 <- c("gumbel", "frechet", "kumar", "laplace", "lomax", "pareto", "rayleigh", "triang", "gompertz", "power", "invgamma", "hnorm", "hcauchy", "fatigue", "wald", "betapr")
npar <- c(2, 3, 2, 2, 2, 2, 1, 3, 2, 2, 2, 1, 1, 3, 2, 3)
for (rep in 1:4) for (di in 0:15) {
  nm <- names0[di + 1]
  pr <- switch(di + 1, c(0.4, 1.3), c(2.5, 0.2, 1.4), c(1.7, 2.3), c(-0.3, 0.9), c(0.8, 2.6), c(2.2, 1.1), 1.4, c(0.1, 3.2, 1.1), c(0.7, 1.2), c(1.8, 4.5), c(2.6, 1.7), 1.3, 0.9, c(0.8, 1.9, 0.2), c(1.3, 2.2), c(2.4, 3.1, 1.2))
  pr <- pr * runif(length(pr), 0.85, 1.15)
  if (di == 7) pr <- c(0.1, 3.2, 1.1) * c(1, 1, 1)
  xs <- switch(di + 1, c(-1, 0.5, 2, 5), c(0.3, 0.8, 2, 6), c(0.2, 0.5, 0.8, 0.95), c(-2, -0.3, 0.4, 3), c(0.1, 1, 3, 9), c(1.2, 2, 5, 12), c(0.3, 1, 2.5, 4), c(0.3, 1.1, 2, 3), c(0.1, 0.8, 2, 4), c(0.4, 1.5, 3, 4.2), c(0.2, 0.7, 2, 6), c(0.2, 0.9, 2, 4), c(0.2, 0.9, 2, 7), c(0.5, 1.3, 2.5, 7), c(0.3, 1, 2.5, 6), c(0.2, 1, 3, 9))
  pp3 <- c(pr, rep(0, 3 - length(pr)))
  if (di == 7) { xs <- c(0.5, 1.1, 2, 3); pr <- c(0.1, 3.2, 1.1) }
  for (xx in xs) {
    add("d", c(di, pp3, xx), do.call(get(paste0("d", nm)), c(list(xx), as.list(pr))))
    add("p", c(di, pp3, xx), do.call(get(paste0("p", nm)), c(list(xx), as.list(pr))))
  }
  if (di != 14) for (pq in c(0.03, 0.3, 0.6, 0.95)) add("q", c(di, pp3, pq), do.call(get(paste0("q", nm)), c(list(pq), as.list(pr))))
}
# discrete and truncated families: fn "d2" "p2" "q2"; args (dist, p1, p2, p3, p4, v): 0 maxwell(sigma) 1 bbinom(size, alpha, beta) 2 bnbinom(size, alpha, beta) 3 dlaplace(scale) 4 lgser(theta) 5 tnorm(mean, sd, a, b); q only for 0 and 5
add2 <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
for (rep in 1:3) {
  n <- sample(5:20, 1); a <- runif(1, 0.5, 3); b <- runif(1, 0.5, 3); for (xx in c(0, 1, 3, n - 1, n)) { add2("d2", c(1, n, a, b, 0, xx), dbbinom(xx, n, a, b)); add2("p2", c(1, n, a, b, 0, xx), pbbinom(xx, n, a, b)) }
  r <- runif(1, 1, 6); a <- runif(1, 1.5, 4); b <- runif(1, 0.5, 3); for (xx in c(0, 1, 4, 10)) { add2("d2", c(2, r, a, b, 0, xx), dbnbinom(xx, r, a, b)); add2("p2", c(2, r, a, b, 0, xx), pbnbinom(xx, r, a, b)) }
  sc <- runif(1, 0.2, 0.8); for (xx in c(-3, -1, 0, 2, 5)) { add2("d2", c(3, sc, 0, 0, 0, xx), ddlaplace(xx, 0, sc)); add2("p2", c(3, sc, 0, 0, 0, xx), pdlaplace(xx, 0, sc)) }
  th <- runif(1, 0.2, 0.9); for (xx in c(1, 2, 5, 9)) { add2("d2", c(4, th, 0, 0, 0, xx), dlgser(xx, th)); add2("p2", c(4, th, 0, 0, 0, xx), plgser(xx, th)) }
  mu <- rnorm(1); sdv <- runif(1, 0.5, 2); lo <- mu - runif(1, 0.5, 2); hi <- mu + runif(1, 0.5, 2); pr <- c(mu, sdv, lo, hi)
  for (xx in seq(lo, hi, length.out = 4)) { add2("d2", c(5, pr, xx), dtnorm(xx, mu, sdv, lo, hi)); add2("p2", c(5, pr, xx), ptnorm(xx, mu, sdv, lo, hi)) }
  for (pq in c(0.1, 0.5, 0.8)) add2("q2", c(5, pr, pq), qtnorm(pq, mu, sdv, lo, hi))
}
# zero-inflated, gamma-Poisson and truncated Poisson masses: fn "d3"; args (dist, p1, p2, p3, v): 0 zip(lambda, pi) 1 zib(size, prob, pi) 2 zinb(size, prob, pi) 3 gpois(shape, scale) 4 tpois(lambda, a, b)
for (rep in 1:3) {
  l <- runif(1, 0.5, 5); pz <- runif(1, 0.05, 0.6); n <- sample(5:20, 1); pr <- runif(1, 0.2, 0.8); sh <- runif(1, 1, 5); sc <- runif(1, 0.3, 2); a <- sample(0:2, 1); b <- sample(8:15, 1)
  for (xx in c(0, 1, 2, 5, 9)) {
    add2("d3", c(0, l, pz, 0, xx), dzip(xx, l, pz)); add2("d3", c(1, n, pr, pz, xx), dzib(xx, n, pr, pz)); add2("d3", c(2, n, pr, pz, xx), dzinb(xx, n, pr, pz))
    add2("d3", c(3, sh, sc, 0, xx), dgpois(xx, sh, scale = sc)); add2("d3", c(4, l, a, b, xx), dtpois(xx, l, a, b))
  }
}
for (rep in 1:4) { m1 <- runif(1, 0.5, 6); m2 <- runif(1, 0.5, 6); for (xx in c(-6, -2, 0, 1, 3, 7)) add2("d3", c(5, m1, m2, 0, xx), dskellam(xx, m1, m2)) }
emit("extradistr", "extraDistr", list(cases))
