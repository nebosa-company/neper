# MCMCpack conjugate Monte Carlo samplers under set.seed (R's own generator) and the BayesFactor / PostProbMod helpers. Every case wants a position-weighted sum.
#   "mcbb" (seed, mc, alpha, beta, m, y[m], n[m]); "mcpg" (seed, mc, alpha, beta, y...); "mcnn" (seed, mc, sigma2, mu0, tau20, y...); "mcmd" (seed, mc, d, y[d], alpha0[d]) the mc by d matrix;
#   "sumx" (x...) the weighted sum of summary(mcmc(x)) statistics then quantiles (9 values); "hpd" (prob, x...) the weighted sum of lower, upper of HPDinterval;
#   "bfmat" (logml...) the weighted sum of BF.mat then BF.log.mat (2 m * m values); "ppm" (m, np, prior[np], logml[m]) the weighted sum of PostProbMod
suppressMessages(library(MCMCpack))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
wsum <- function(m) sum(seq_along(m) * as.vector(t(m)))
set.seed(20261126)
for (rep in 1:10) {
  seed <- sample(1:100000, 1); mc <- sample(20:200, 1)
  m <- sample(1:4, 1); nn <- sample(5:40, m, replace = TRUE); yy <- sapply(nn, function(k) sample(0:k, 1)); al <- round(runif(1, 0.3, 3), 2); be <- round(runif(1, 0.3, 3), 2)
  set.seed(seed); add("mcbb", c(seed, mc, al, be, m, yy, nn), wsum(MCbinomialbeta(yy, nn, al, be, mc)))
  yc <- rpois(sample(3:10, 1), 3); al2 <- round(runif(1, 0.3, 4), 2); be2 <- round(runif(1, 0.3, 3), 2)
  set.seed(seed); add("mcpg", c(seed, mc, al2, be2, yc), wsum(MCpoissongamma(yc, al2, be2, mc)))
  yn <- round(rnorm(sample(3:12, 1), 1, 2), 3); s2 <- round(runif(1, 0.5, 3), 2); mu0 <- round(rnorm(1), 2); t20 <- round(runif(1, 0.5, 4), 2)
  set.seed(seed); add("mcnn", c(seed, mc, s2, mu0, t20, yn), wsum(MCnormalnormal(yn, s2, mu0, t20, mc)))
  d <- sample(2:5, 1); ym <- rpois(d, 5); a0 <- round(runif(d, 0.4, 3), 2)
  set.seed(seed); add("mcmd", c(seed, mc, d, ym, a0), wsum(MCmultinomdirichlet(ym, a0, mc)))
  M <- sample(2:5, 1); lm <- round(rnorm(M, -100, 5), 3)
  mk <- function(l) { o <- structure(matrix(0, 1, 1), class = "mcmc"); attr(o, "logmarglike") <- l; attr(o, "call") <- "x"; attr(o, "y") <- 1; o }
  bf <- do.call(BayesFactor, lapply(lm, mk))
  add("bfmat", lm, sum(seq_along(bf$BF.mat) * as.vector(t(bf$BF.mat))) + sum(seq_along(bf$BF.log.mat) * as.vector(t(bf$BF.log.mat))))
  np <- sample(1:M, 1); pr <- round(runif(np, 0.5, 3), 2)
  add("ppm", c(M, np, pr, lm), sum(seq_along(PostProbMod(bf, pr)) * as.vector(PostProbMod(bf, pr))))
}
for (rep in 1:10) {
  n <- sample(30:300, 1); x <- as.vector(arima.sim(list(ar = runif(1, 0, 0.8)), n)) * runif(1, 0.5, 3) + rnorm(1)
  sm <- summary(coda::mcmc(x))
  add("sumx", x, sum(seq_len(9) * c(sm$statistics, sm$quantiles)))
  pr <- sample(c(0.8, 0.9, 0.95, 0.99, 0.5, 0.123), 1)
  h <- coda::HPDinterval(coda::mcmc(x), prob = pr)
  add("hpd", c(pr, x), sum(1:2 * as.vector(h)))
}
emit("mcmcpackhelp", "MCMCpack", list(cases))
