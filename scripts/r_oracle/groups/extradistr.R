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
# fn "m4" (dist, p1, p2, p3, kind 0 d 1 p 2 q, v): 0 gev 1 gpd 2 dunif 3 bern 4 dweibull 5 lst 6 invchisq
for (rep in 1:5) {
  mu <- rnorm(1); sg <- runif(1, 0.5, 2); xi <- c(-0.3, 0.2, 0, 0.5, -0.1)[rep]
  for (xx in mu + sg * c(-1.5, -0.5, 0.2, 1, 3)) { add2("m4", c(0, mu, sg, xi, 0, xx), dgev(xx, mu, sg, xi)); add2("m4", c(0, mu, sg, xi, 1, xx), pgev(xx, mu, sg, xi)); add2("m4", c(1, mu, sg, xi, 0, xx), dgpd(xx, mu, sg, xi)); add2("m4", c(1, mu, sg, xi, 1, xx), pgpd(xx, mu, sg, xi)) }
  for (pq in c(0.1, 0.5, 0.9)) { add2("m4", c(0, mu, sg, xi, 2, pq), qgev(pq, mu, sg, xi)); add2("m4", c(1, mu, sg, xi, 2, pq), qgpd(pq, mu, sg, xi)); add2("m4", c(5, 1 + rep, mu, sg, 2, pq), qlst(pq, 1 + rep, mu, sg)); add2("m4", c(6, 2 + rep, 0.5 + rep / 4, 0, 2, pq), qinvchisq(pq, 2 + rep, 0.5 + rep / 4)) }
  lo <- sample(-3:2, 1); hi <- lo + sample(3:9, 1); q <- runif(1, 0.3, 0.9); be <- runif(1, 0.5, 2); nu <- 1 + rep
  for (xx in c(lo - 1, lo, lo + 1.0, hi, hi + 1, 0, 1, 2, 3)) { add2("m4", c(2, lo, hi, 0, 0, xx), ddunif(xx, lo, hi)); add2("m4", c(2, lo, hi, 0, 1, xx), pdunif(xx, lo, hi)); add2("m4", c(3, q, 0, 0, 0, xx), dbern(xx, q))
    add2("m4", c(4, q, be, 0, 0, xx), ddweibull(xx, q, be)); add2("m4", c(4, q, be, 0, 1, xx), pdweibull(xx, q, be)) }
  for (xx in c(-2, -0.5, 0.3, 1.7, 4)) { add2("m4", c(5, nu, mu, sg, 0, xx), dlst(xx, nu, mu, sg)); add2("m4", c(5, nu, mu, sg, 1, xx), plst(xx, nu, mu, sg)) }
  for (xx in c(0.2, 0.7, 1.5, 4)) { add2("m4", c(6, nu, 0.5 + rep / 4, 0, 0, xx), dinvchisq(xx, nu, 0.5 + rep / 4)); add2("m4", c(6, nu, 0.5 + rep / 4, 0, 1, xx), pinvchisq(xx, nu, 0.5 + rep / 4)) }
}
# fn "m6" (dist, kind 0 d 1 p, p1..p4, a1, v): 0 ddnorm 1 ddgamma 2 huber 3 mixnorm 4 mixpois
for (rep in 1:4) {
  mu <- rnorm(1); sg <- runif(1, 0.6, 2); ep <- runif(1, 0.7, 2); sh <- runif(1, 1, 4); rt <- runif(1, 0.5, 2); a1 <- runif(1, 0.2, 0.8); m2 <- rnorm(1, 2); s2 <- runif(1, 0.4, 1.5); l1 <- runif(1, 0.5, 3); l2 <- runif(1, 3, 8)
  for (xx in c(0, 1, 2, 3, 6)) { add2("m6", c(0, 0, mu, sg, 0, 0, 0, xx), ddnorm(xx, mu, sg)); add2("m6", c(0, 1, mu, sg, 0, 0, 0, xx), pdnorm(xx, mu, sg)); add2("m6", c(1, 0, sh, 1 / rt, 0, 0, 0, xx), ddgamma(xx, sh, rt)); add2("m6", c(1, 1, sh, 1 / rt, 0, 0, 0, xx), pdgamma(xx, sh, rt))
    add2("m6", c(4, 0, l1, l2, 0, 0, a1, xx), dmixpois(xx, c(l1, l2), c(a1, 1 - a1))) }
  for (xx in mu + sg * c(-4, -1.7, -0.5, 0.3, 1.2, 3.5)) { add2("m6", c(2, 0, mu, sg, ep, 0, 0, xx), dhuber(xx, mu, sg, ep)); add2("m6", c(2, 1, mu, sg, ep, 0, 0, xx), phuber(xx, mu, sg, ep)); add2("m6", c(3, 0, mu, sg, m2, s2, a1, xx), dmixnorm(xx, c(mu, m2), c(sg, s2), c(a1, 1 - a1))) }
}
# fn "mv" (dist, k, size, x[k], par[k]) and "bv" (dist, v1..v7)
for (rep in 1:6) {
  k <- sample(2:5, 1); al <- runif(k, 0.5, 4); xd <- rgamma(k, al); xd <- xd / sum(xd); pr <- runif(k); pr <- pr / sum(pr); size <- sample(3:12, 1); xm <- as.numeric(rmultinom(1, size, pr)); nn <- sample(2:6, k, TRUE); kk <- sample(1:sum(nn), 1)
  xh <- as.numeric(rmvhyper(1, nn, kk))
  add2("mv", c(0, k, 0, xd, al), ddirichlet(xd, al)); add2("mv", c(1, k, size, xm, pr), dmnom(xm, size, pr)); add2("mv", c(2, k, size, xm, al), ddirmnom(xm, size, al)); add2("mv", c(3, k, kk, xh, nn), dmvhyper(xh, nn, kk))
  m1 <- rnorm(1); m2 <- rnorm(1); s1 <- runif(1, 0.5, 2); s2 <- runif(1, 0.5, 2); r <- runif(1, -0.8, 0.8); xx <- rnorm(1); yy <- rnorm(1)
  add2("bv", c(0, xx, yy, m1, m2, s1, s2, r), dbvnorm(xx, yy, m1, m2, s1, s2, r))
  a <- runif(1, 0.3, 2); b <- runif(1, 0.3, 2); cc <- runif(1, 0.2, 1.5); for (ij in list(c(0, 0), c(1, 2), c(3, 1), c(4, 5))) add2("bv", c(1, ij, a, b, cc, 0, 0), dbvpois(ij[1], ij[2], a, b, cc))
}
# fn "nh" (kind 0 d 1 p 2 q 3 tlambda q, n, m, r, v)
for (rep in 1:5) {
  n <- sample(5:15, 1); m <- sample(3:10, 1); r <- sample(1:m, 1); lam <- c(-0.4, 0.3, 1.2, 0.8, 2)[rep]
  for (xx in r:(r + 6)) { add2("nh", c(0, n, m, r, xx), dnhyper(xx, n, m, r)); add2("nh", c(1, n, m, r, xx), pnhyper(xx, n, m, r)) }
  for (pq in c(0.1, 0.4, 0.8)) { add2("nh", c(2, n, m, r, pq), qnhyper(pq, n, m, r)); add2("nh", c(3, lam, 0, 0, pq), qtlambda(pq, lam)) }
}
# fn "pb" (dist 0 prop 1 bhatt, kind 0 d 1 p 2 q, p1, p2, p3, v)
for (rep in 1:4) {
  size <- runif(1, 5, 30); mn <- runif(1, 0.2, 0.8); pri <- sample(c(0, 1, 2), 1); mu <- rnorm(1); sg <- runif(1, 0.5, 2); aa <- runif(1, 0.3, 2)
  for (xx in c(0.1, 0.3, 0.55, 0.9)) { add2("pb", c(0, 0, size, mn, pri, xx), dprop(xx, size, mn, pri)); add2("pb", c(0, 1, size, mn, pri, xx), pprop(xx, size, mn, pri)) }
  for (pq in c(0.1, 0.5, 0.9)) add2("pb", c(0, 2, size, mn, pri, pq), qprop(pq, size, mn, pri))
  for (xx in mu + c(-4, -1, 0, 0.7, 3)) { add2("pb", c(1, 0, mu, sg, aa, xx), dbhatt(xx, mu, sg, aa)); add2("pb", c(1, 1, mu, sg, aa, xx), pbhatt(xx, mu, sg, aa)) }
}
# random draws: "rg" (family, seed, p1, p2, p3, index) the draw at position index (0-based) of five seeded draws; family 0 gumbel 1 frechet 2 power 3 lomax 4 pareto 5 rayleigh 6 kumar 7 gompertz 8 hnorm 9 hcauchy 10 laplace
for (rep in 1:33) {
  sd <- sample(1:100000, 1); fam <- (rep - 1) %% 11; p1 <- runif(1, 0.5, 3); p2 <- runif(1, 0.5, 3); p3 <- runif(1, -1, 1)
  set.seed(sd); v <- switch(fam + 1, rgumbel(5, p1, p2), rfrechet(5, p1, p3, p2), rpower(5, p1, p2), rlomax(5, p1, p2), rpareto(5, p1, p2), rrayleigh(5, p1), rkumar(5, p1, p2), rgompertz(5, p1, p2), rhnorm(5, p1), rhcauchy(5, p1), rlaplace(5, p1, p2))
  for (j in 1:5) if (is.finite(v[j])) cases[[length(cases) + 1]] <- case("rg", c(fam, sd, if (fam == 1) p1 else p1, if (fam == 1) p3 else p2, if (fam == 1) p2 else 0, j - 1), v[j], rel = 1e-10, abs = 1e-12)
}
# GEV (11) and GPD (12) draws: (family, seed, mu, sigma, xi, index)
for (rep in 1:12) { sd <- sample(1:100000, 1); mu <- rnorm(1); sg <- runif(1, 0.5, 2); xi <- c(-0.4, 0.3, 0.6, -0.2)[rep %% 4 + 1]; fam <- 11 + rep %% 2
  set.seed(sd); v <- if (fam == 11) rgev(5, mu, sg, xi) else rgpd(5, mu, sg, xi)
  for (j in 1:5) if (is.finite(v[j])) cases[[length(cases) + 1]] <- case("rg", c(fam, sd, mu, sg, xi, j - 1), v[j], rel = 1e-10, abs = 1e-12) }
# discrete uniform (13), Bernoulli (14), discrete Weibull (15) and Tukey lambda (16) draws: (family, seed, p1, p2, p3, index)
for (rep in 1:30) { sd <- sample(1:100000, 1); fam <- 13 + (rep - 1) %% 4
  lo <- sample(-3:3, 1); hi <- lo + sample(3:9, 1); pr <- runif(1, 0.2, 0.8); q <- runif(1, 0.4, 0.9); be <- runif(1, 0.6, 2); lam <- runif(1, -0.5, 1.5); mu <- rnorm(1); sg <- runif(1, 0.5, 2); aa <- runif(1, 0.3, 2)
  set.seed(sd); v <- switch(fam - 12, rdunif(5, lo, hi), rbern(5, pr), rdweibull(5, q, be), rtlambda(5, lam))
  pp <- switch(fam - 12, c(lo, hi, 0), c(pr, 0, 0), c(q, be, 0), c(lam, 0, 0))
  for (j in 1:5) if (is.finite(v[j])) cases[[length(cases) + 1]] <- case("rg", c(fam, sd, pp, j - 1), v[j], rel = 1e-10, abs = 1e-12) }
# truncated binomial (0), truncated Poisson (1) and logarithmic series (2) draws: "rg4" (family, seed, p1, p2, p3, p4, index)
for (rep in 1:30) { sd <- sample(1:100000, 1); fam <- (rep - 1) %% 3; n <- sample(8:20, 1); pr <- runif(1, 0.2, 0.8); a <- sample(0:2, 1); b <- sample(6:n, 1); l <- runif(1, 1, 5); bb <- sample(7:15, 1); th <- runif(1, 0.2, 0.9)
  set.seed(sd); v <- switch(fam + 1, rtbinom(5, n, pr, a, b), rtpois(5, l, a, bb), rlgser(5, th)); pp <- switch(fam + 1, c(n, pr, a, b), c(l, a, bb, 0), c(th, 0, 0, 0))
  for (j in 1:5) cases[[length(cases) + 1]] <- case("rg4", c(fam, sd, pp, j - 1), v[j], rel = 0, abs = 0) }
# generators through R's gamma, t, normal and beta: "rg6" (family 0 invgamma 1 invchisq 2 lst 3 ht 4 fatigue 5 nsbeta, seed, p1..p4, index)
for (rep in 1:42) { sd <- sample(1:100000, 1); fam <- (rep - 1) %% 7; a1 <- runif(1, 1.5, 6); b1 <- runif(1, 0.5, 3); m1 <- rnorm(1); s1 <- runif(1, 0.5, 2); lo <- runif(1, -2, 0); hi <- lo + runif(1, 1, 3)
  set.seed(sd); v <- switch(fam + 1, rinvgamma(5, a1, b1), rinvchisq(5, a1, b1), rlst(5, a1, m1, s1), rht(5, a1, s1), rfatigue(5, a1 / 3, b1, m1), rnsbeta(5, a1, b1, lo, hi), rbetapr(5, a1, b1, s1))
  pp <- switch(fam + 1, c(a1, b1, 0, 0), c(a1, b1, 0, 0), c(a1, m1, s1, 0), c(a1, s1, 0, 0), c(a1 / 3, b1, m1, 0), c(a1, b1, lo, hi), c(a1, b1, s1, 0))
  for (j in 1:5) cases[[length(cases) + 1]] <- case("rg6", c(fam, sd, pp, j - 1), v[j], rel = 1e-9, abs = 1e-12) }
# scalar generators over several base draws: "rg7" (family, seed, p1, p2, p3, index); 0 triang 1 dlaplace 2 zip 3 zib 4 zinb 5 wald 6 bbinom 7 bnbinom 8 gpois 9 skellam 10 slash 11 prop 12 sign 13 sgomp 14 bhatt 15 huber 16 dnorm 17 dgamma 18 nhyper
for (rep in 1:76) { sd <- sample(1:100000, 1); fam <- (rep - 1) %% 19
  l <- runif(1, 0.5, 5); pz <- runif(1, 0.05, 0.6); n <- sample(5:20, 1); pr <- runif(1, 0.2, 0.8); a1 <- runif(1, 0.5, 3); b1 <- runif(1, 0.5, 3); mu <- rnorm(1); sg <- runif(1, 0.5, 2); ep <- runif(1, 0.7, 2)
  lo <- runif(1, -1, 0); hi <- lo + runif(1, 1, 4); md <- lo + (hi - lo) * runif(1, 0.1, 0.9); nh <- sample(5:15, 1); mh <- sample(3:10, 1); rh <- sample(1:mh, 1)
  pp <- switch(fam + 1, c(lo, hi, md), c(mu, pr, 0), c(l, pz, 0), c(n, pr, pz), c(n, pr, pz), c(a1, b1, 0), c(n, a1, b1), c(n, a1, b1), c(a1, b1, 0), c(l, a1, 0), c(mu, sg, 0), c(n, pr, ep), c(0, 0, 0), c(pr, b1, 0), c(mu, sg, a1), c(mu, sg, ep), c(mu * 5, sg * 3, 0), c(a1 * 2, b1, 0), c(nh, mh, rh))
  set.seed(sd)
  v <- switch(fam + 1, rtriang(5, lo, hi, md), rdlaplace(5, mu, pr), rzip(5, l, pz), rzib(5, n, pr, pz), rzinb(5, n, pr, pz), rwald(5, a1, b1), rbbinom(5, n, a1, b1), rbnbinom(5, n, a1, b1), rgpois(5, a1, scale = b1), rskellam(5, l, a1), rslash(5, mu, sg), rprop(5, n, pr, ep), rsign(5), rsgomp(5, pr, b1), rbhatt(5, mu, sg, a1), rhuber(5, mu, sg, ep), rdnorm(5, mu * 5, sg * 3), rdgamma(5, a1 * 2, scale = b1), rnhyper(5, nh, mh, rh))
  for (j in 1:5) cases[[length(cases) + 1]] <- case("rg7", c(fam, sd, pp, j - 1), v[j], rel = 1e-10, abs = 1e-12) }
# vector generators: "rv" (family, seed, k, draw, column, par...); 0 dirichlet 1 mnom 2 dirmnom 3 mvhyper 4 bvnorm 5 mixnorm 6 mixpois 7 cat 8 catlp 9 cat over a matrix
addv <- function(fam, sd, k, m, par) { m <- as.matrix(m); for (i in 1:nrow(m)) for (j in 1:ncol(m)) cases[[length(cases) + 1]] <<- case("rv", c(fam, sd, k, i - 1, j - 1, par), as.numeric(m[i, j]), rel = 1e-10, abs = 1e-12) }
for (rep in 1:30) { sd <- sample(1:100000, 1); fam <- (rep - 1) %% 10; k <- sample(2:5, 1); size <- sample(3:12, 1)
  al <- runif(k, 0.5, 4); pr <- runif(k); pr <- pr / sum(pr); nn <- sample(2:6, k, TRUE); kk <- sample(1:sum(nn), 1); mu <- rnorm(k); sg <- runif(k, 0.5, 2); lam <- runif(k, 0.5, 8)
  mat <- matrix(runif(2 * k), 2, k); mat <- mat / rowSums(mat); bv <- c(rnorm(2), runif(2, 0.5, 2), runif(1, -0.8, 0.8))
  set.seed(sd)
  if (fam == 0) addv(0, sd, k, rdirichlet(3, al), al)
  if (fam == 1) addv(1, sd, k, rmnom(3, size, pr), c(size, pr))
  if (fam == 2) addv(2, sd, k, rdirmnom(3, size, al), c(size, al))
  if (fam == 3) addv(3, sd, k, rmvhyper(3, nn, kk), c(kk, nn))
  if (fam == 4) addv(4, sd, 2, rbvnorm(3, bv[1], bv[2], bv[3], bv[4], bv[5]), bv)
  if (fam == 5) addv(5, sd, k, matrix(rmixnorm(4, mu, sg, pr), ncol = 1), c(mu, sg, pr))
  if (fam == 6) addv(6, sd, k, matrix(rmixpois(4, lam, pr), ncol = 1), c(lam, pr))
  if (fam == 7) addv(7, sd, k, matrix(rcat(4, pr), ncol = 1), pr)
  if (fam == 8) addv(8, sd, k, matrix(rcatlp(4, log(pr)), ncol = 1), log(pr))
  if (fam == 9) addv(9, sd, k, matrix(rcat(5, mat), ncol = 1), c(2, as.vector(t(mat)))) }
emit("extradistr", "extraDistr", list(cases))
