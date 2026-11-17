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
# more densities and masses: fn "d3" with dist 6 tbinom(size, prob, a, b) [args: dist, size, prob, a, b, v] needs a 6-slot layout, so these use fn "d4": (dist, p1, p2, p3, p4, v): 0 tbinom(size, prob, a, b) 1 nsbeta(s1, s2, min, max) 2 ht(nu, sigma) 3 slash(mu, sigma) 4 sgomp(b, eta)
for (rep in 1:3) {
  n <- sample(8:20, 1); pr <- runif(1, 0.2, 0.8); a <- sample(0:2, 1); b <- sample(5:n, 1); for (xx in c(0, 1, 3, 5, n)) add2("d4", c(0, n, pr, a, b, xx), dtbinom(xx, n, pr, a, b))
  s1 <- runif(1, 0.8, 4); s2 <- runif(1, 0.8, 4); lo <- runif(1, -2, 0); hi <- lo + runif(1, 1, 4); for (xx in seq(lo, hi, length.out = 5)) add2("d4", c(1, s1, s2, lo, hi, xx), dnsbeta(xx, s1, s2, lo, hi))
  nu <- runif(1, 1, 8); sg <- runif(1, 0.5, 2); for (xx in c(0, 0.5, 2, 5)) add2("d4", c(2, nu, sg, 0, 0, xx), dht(xx, nu, sg))
  mu <- rnorm(1); for (xx in c(mu - 3, mu - 0.2, mu, mu + 1, mu + 4)) add2("d4", c(3, mu, sg, 0, 0, xx), dslash(xx, mu, sg))
  bb <- runif(1, 0.3, 2); et <- runif(1, 0.2, 3); for (xx in c(0, 0.3, 1, 3)) add2("d4", c(4, bb, et, 0, 0, xx), dsgomp(xx, bb, et))
}
# cumulative forms: fn "c3" (dist, p1, p2, p3, v) 0 zip 1 zib 2 zinb 3 gpois 4 tpois; fn "c4" (dist, p1..p4, v) 0 tbinom 1 nsbeta 2 ht 3 sgomp
for (rep in 1:4) {
  l <- runif(1, 0.5, 5); pz <- runif(1, 0.05, 0.6); n <- sample(8:20, 1); pr <- runif(1, 0.2, 0.8); sh <- runif(1, 1, 5); sc <- runif(1, 0.3, 2); a <- sample(0:2, 1); b <- sample(8:15, 1)
  for (xx in c(-1, 0, 1, 2, 5, 9, 14)) {
    add2("c3", c(0, l, pz, 0, xx), pzip(xx, l, pz)); add2("c3", c(1, n, pr, pz, xx), pzib(xx, n, pr, pz)); add2("c3", c(2, n, pr, pz, xx), pzinb(xx, n, pr, pz))
    add2("c3", c(3, sh, sc, 0, xx), pgpois(xx, sh, scale = sc)); add2("c3", c(4, l, a, b, xx), ptpois(xx, l, a, b))
    add2("c4", c(0, n, pr, a, b, xx), ptbinom(xx, n, pr, a, b))
  }
  s1 <- runif(1, 0.8, 4); s2 <- runif(1, 0.8, 4); lo <- runif(1, -2, 0); hi <- lo + runif(1, 1, 4); for (xx in seq(lo - 0.5, hi + 0.5, length.out = 6)) add2("c4", c(1, s1, s2, lo, hi, xx), pnsbeta(xx, s1, s2, lo, hi))
  nu <- runif(1, 1, 8); sg <- runif(1, 0.5, 2); for (xx in c(-1, 0.5, 2, 5)) add2("c4", c(2, nu, sg, 0, 0, xx), pht(xx, nu, sg))
  bb <- runif(1, 0.3, 2); et <- runif(1, 0.2, 3); for (xx in c(-1, 0.3, 1, 3)) add2("c4", c(3, bb, et, 0, 0, xx), psgomp(xx, bb, et))
}
# quantile functions: fn "k3" as "c3" and "k4" 0 tbinom 1 nsbeta 2 ht
for (rep in 1:4) {
  l <- runif(1, 0.5, 5); pz <- runif(1, 0.05, 0.6); n <- sample(8:20, 1); pr <- runif(1, 0.2, 0.8); sh <- runif(1, 1, 5); sc <- runif(1, 0.3, 2); a <- sample(0:2, 1); b <- sample(8:15, 1)
  for (xx in c(0.05, 0.2, 0.45, 0.7, 0.95)) {
    add2("k3", c(0, l, pz, 0, xx), qzip(xx, l, pz)); add2("k3", c(1, n, pr, pz, xx), qzib(xx, n, pr, pz)); add2("k3", c(2, n, pr, pz, xx), qzinb(xx, n, pr, pz))
    add2("k3", c(4, l, a, b, xx), qtpois(xx, l, a, b))
    add2("k4", c(0, n, pr, a, b, xx), qtbinom(xx, n, pr, a, b))
    s1 <- 1 + rep / 2; s2 <- 2 + rep / 3; add2("k4", c(1, s1, s2, -1, 2.5, xx), qnsbeta(xx, s1, s2, -1, 2.5)); add2("k4", c(2, 1 + rep, 1.3, 0, 0, xx), qht(xx, 1 + rep, 1.3))
  }
}
# random draws: "rg" (family, seed, p1, p2, p3, index) the draw at position index (0-based) of five seeded draws; family 0 gumbel 1 frechet 2 power 3 lomax 4 pareto 5 rayleigh 6 kumar 7 gompertz 8 hnorm 9 hcauchy 10 laplace
for (rep in 1:33) {
  sd <- sample(1:100000, 1); fam <- (rep - 1) %% 11; p1 <- runif(1, 0.5, 3); p2 <- runif(1, 0.5, 3); p3 <- runif(1, -1, 1)
  set.seed(sd); v <- switch(fam + 1, rgumbel(5, p1, p2), rfrechet(5, p1, p3, p2), rpower(5, p1, p2), rlomax(5, p1, p2), rpareto(5, p1, p2), rrayleigh(5, p1), rkumar(5, p1, p2), rgompertz(5, p1, p2), rhnorm(5, p1), rhcauchy(5, p1), rlaplace(5, p1, p2))
  for (j in 1:5) if (is.finite(v[j])) cases[[length(cases) + 1]] <- case("rg", c(fam, sd, if (fam == 1) p1 else p1, if (fam == 1) p3 else p2, if (fam == 1) p2 else 0, j - 1), v[j], rel = 1e-10, abs = 1e-12)
}
emit("extradistr", "extraDistr", list(cases))
