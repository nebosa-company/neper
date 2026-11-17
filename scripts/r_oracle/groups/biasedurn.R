# BiasedUrn: Fisher's and Wallenius' noncentral hypergeometric d, p, q, mean, var (and Fisher's mode and odds).
#   args: (kind, m1, m2, n, w, arg)  kinds 12 modeW, 0 dF 1 pF 2 qF 3 meanF 4 varF 5 modeF 6 dW 7 pW 8 qW 9 meanW 10 varW 11 oddsF (arg = x)
suppressMessages(library(BiasedUrn))
cases <- list()
set.seed(20261116)
addc <- function(k, a, want, tol) cases[[length(cases) + 1]] <<- case(paste0("k", k), a, want, rel = tol, abs = tol)
for (rep in 1:40) {
  m1 <- sample(5:40, 1); m2 <- sample(5:40, 1); n <- sample(3:min(m1 + m2 - 1, 30), 1); w <- sample(c(0.2, 0.5, 1.5, 2.5, 7), 1)
  lo <- max(0, n - m2); hi <- min(n, m1); x <- sample(lo:hi, 1); pr <- round(runif(1, 0.05, 0.95), 3)
  a <- function(k, arg) c(k, m1, m2, n, w, arg)
  addc(0, a(0, x), dFNCHypergeo(x, m1, m2, n, w), 1e-9); addc(1, a(1, x), pFNCHypergeo(x, m1, m2, n, w), 1e-9)
  addc(2, a(2, pr), qFNCHypergeo(pr, m1, m2, n, w), 1e-9); addc(3, a(3, 0), meanFNCHypergeo(m1, m2, n, w, precision = 1e-14), 1e-9)
  addc(4, a(4, 0), varFNCHypergeo(m1, m2, n, w, precision = 1e-14), 1e-9); addc(5, a(5, 0), modeFNCHypergeo(m1, m2, n, w), 1e-9)
  addc(6, a(6, x), dWNCHypergeo(x, m1, m2, n, w, precision = 1e-12), 1e-7); addc(7, a(7, x), pWNCHypergeo(x, m1, m2, n, w, precision = 1e-12), 1e-7)
  addc(8, a(8, pr), qWNCHypergeo(pr, m1, m2, n, w, precision = 1e-12), 1e-7); addc(9, a(9, 0), meanWNCHypergeo(m1, m2, n, w, precision = 1e-12), 1e-7)
  addc(10, a(10, 0), varWNCHypergeo(m1, m2, n, w, precision = 1e-12), 1e-7)
  addc(12, a(12, 0), modeWNCHypergeo(m1, m2, n, w), 0)
  if (x > lo && x < hi) addc(11, a(11, x), oddsFNCHypergeo(x, m1, m2, n), 1e-6)
}
# the multivariate mass functions ("mv": (kind 0 Fisher 1 Wallenius, what 0 d, idx, n, c, m[c], odds[c], xq[c])); the multivariate means and variances of the package are approximations (they differ from the exact sums by up to 0.04) and are not compared
for (rep in 1:30) {
  cc <- sample(3:4, 1); m <- sample(2:7, cc, TRUE); n <- sample(2:min(10, sum(m) - 1), 1); od <- round(runif(cc, 0.3, 4), 2)
  xq <- as.numeric(rmultinom(1, n, m / sum(m))); while (any(xq > m)) xq <- as.numeric(rmultinom(1, n, m / sum(m)))
  mvn <- function(kind, what, idx, want, tol) cases[[length(cases) + 1]] <<- case("mv", c(kind, what, idx, n, cc, m, od, xq), want, rel = tol, abs = tol)
  mvn(0, 0, 0, dMFNCHypergeo(xq, m, n, od), 1e-8); mvn(1, 0, 0, dMWNCHypergeo(xq, m, n, od), 1e-6)
}
emit("biasedurn", "BiasedUrn", list(cases))
