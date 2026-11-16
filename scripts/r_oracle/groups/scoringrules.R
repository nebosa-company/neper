# scoringRules: closed-form and sample-based proper scores.
#   fn "crps" "logs" "dss": args (family, a, b, c, d, y); family 0 norm(mean, sd) 1 logis(loc, scale) 2 lapl(loc, scale) 3 exp(rate) 4 unif(min, max, lmass, umass)
#   5 lnorm(meanlog, sdlog) 6 gamma(shape, scale) 7 binom(size, prob) crps only 8 pois(lambda) logs and dss only
#   fn "sample": args (kind, alpha, m, d, y[d], data[m*d] row-major); kind 0 crps 1 dss 2 logs 3 es 4 vs (alpha is p) 5 qs 6 rps (y[0] the 1-based category, data the probabilities)
suppressMessages(library(scoringRules))
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261201)
for (rep in 1:5) {
  ys <- c(-1.2, 0.3, 0.9, 2.4) * runif(1, 0.8, 1.2)
  for (y in ys) {
    a <- runif(2, 0.6, 1.8); yp <- abs(y) + 0.1
    P <- function(fam, p, v, ...) {
      args <- c(fam, p, rep(0, 4 - length(p)), v)
      args
    }
    f <- list(
      list(0, c(a[1] - 1, a[2]), y, crps_norm(y, a[1] - 1, a[2]), logs_norm(y, a[1] - 1, a[2]), dss_norm(y, a[1] - 1, a[2])),
      list(1, c(a[1] - 1, a[2]), y, crps_logis(y, a[1] - 1, a[2]), logs_logis(y, a[1] - 1, a[2]), dss_logis(y, a[1] - 1, a[2])),
      list(2, c(a[1] - 1, a[2]), y, crps_lapl(y, a[1] - 1, a[2]), logs_lapl(y, a[1] - 1, a[2]), dss_lapl(y, a[1] - 1, a[2])),
      list(3, a[1], yp, crps_exp(yp, a[1]), logs_exp(yp, a[1]), dss_exp(yp, a[1])),
      list(4, c(-1.5, 2.5, 0.1, 0.2), y, crps_unif(y, -1.5, 2.5, 0.1, 0.2), logs_unif(y, -1.5, 2.5), dss_unif(y, -1.5, 2.5)),
      list(5, c(a[1] - 1, a[2] / 2), yp, crps_lnorm(yp, a[1] - 1, a[2] / 2), logs_lnorm(yp, a[1] - 1, a[2] / 2), dss_lnorm(yp, a[1] - 1, a[2] / 2)),
      list(6, c(a[1] * 2, a[2]), yp, crps_gamma(yp, a[1] * 2, scale = a[2]), logs_gamma(yp, a[1] * 2, scale = a[2]), dss_gamma(yp, a[1] * 2, scale = a[2])))
    for (e in f) {
      ar <- P(e[[1]], e[[2]], e[[3]])
      add("crps", ar, e[[4]]); add("logs", ar, e[[5]]); add("dss", ar, e[[6]])
    }
    add("crps", P(7, c(12, 0.35), round(abs(y) * 4)), crps_binom(round(abs(y) * 4), 12, 0.35))
    add("logs", P(8, 3.4, round(abs(y) * 4)), logs_pois(round(abs(y) * 4), 3.4))
    add("dss", P(8, 3.4, round(abs(y) * 4)), dss_pois(round(abs(y) * 4), 3.4))
  }
  m <- 40; d <- 3
  X <- matrix(rnorm(m * d), d, m) + c(0.2, -0.3, 0.5); yv <- rnorm(d)
  y1 <- rnorm(1); x1 <- rnorm(m, 0.3, 1.2)
  S <- function(kind, alpha, y, dat, m, d) c(kind, alpha, m, d, y, dat)
  add("sample", S(0, 0, y1, x1, m, 1), crps_sample(y1, x1))
  add("sample", S(1, 0, y1, x1, m, 1), dss_sample(y1, x1))
  add("sample", S(2, 0, y1, x1, m, 1), logs_sample(y1, x1))
  add("sample", S(3, 0, yv, as.vector(X), m, d), es_sample(yv, X))
  add("sample", S(4, 0.5, yv, as.vector(X), m, d), vs_sample(yv, X, p = 0.5))
  add("sample", S(4, 1, yv, as.vector(X), m, d), vs_sample(yv, X, p = 1))
  for (al in c(0.1, 0.5, 0.9)) add("sample", S(5, al, y1, x1, m, 1), qs_sample(y1, x1, alpha = al))
  pr <- runif(5); pr <- pr / sum(pr)
  add("sample", S(6, 0, 3, pr, 5, 1), rps_probs(3, pr))
}
for (rep in 1:25) {
  y <- round(abs(rnorm(1, 3, 3))); lam <- runif(1, 0.2, 25); df <- runif(1, 1.5, 12); loc <- rnorm(1); sc <- runif(1, 0.3, 3); yt <- rnorm(1, 0, 3)
  add("crps", P(8, lam, y), crps_pois(y, lam)); add("crps", P(9, c(df, loc, sc), yt), crps_t(yt, df, loc, sc)); add("logs", P(9, c(df, loc, sc), yt), logs_t(yt, df, loc, sc))
}
for (rep in 1:30) {
  loc <- rnorm(1); sc <- runif(1, 0.5, 2.5); lo <- loc + sc * runif(1, -2, 1.5); hi <- lo + sc * runif(1, 0.5, 4); yy <- rnorm(1, loc, 2 * sc)
  lm <- runif(1, 0, 0.3); um <- runif(1, 0, 0.3)
  add("crps", c(10, loc, sc, lo, hi, yy, lm, um), crps_gtcnorm(yy, loc, sc, lo, hi, lm, um))
  add("crps", c(11, loc, sc, lo, hi, yy, 0, 0), crps_tnorm(yy, loc, sc, lo, hi))
  add("crps", c(12, loc, sc, lo, hi, yy, 0, 0), crps_cnorm(yy, loc, sc, lo, hi))
  lh <- loc + sc * runif(1, 3.2, 5); add("crps", c(11, loc, sc, lh, lh + sc * 2, yy + lh - loc, 0, 0), crps_tnorm(yy + lh - loc, loc, sc, lh, lh + sc * 2))
}
for (rep in 1:30) {
  loc <- rnorm(1); sc <- runif(1, 0.5, 2.5); lo <- loc + sc * runif(1, -2, 1.5); hi <- lo + sc * runif(1, 0.5, 4); yy <- rnorm(1, loc, 2 * sc)
  lm <- runif(1, 0, 0.3); um <- runif(1, 0, 0.3)
  add("crps", c(13, loc, sc, lo, hi, yy, lm, um), crps_gtclogis(yy, loc, sc, lo, hi, lm, um))
  add("crps", c(14, loc, sc, lo, hi, yy, 0, 0), crps_tlogis(yy, loc, sc, lo, hi))
  add("crps", c(15, loc, sc, lo, hi, yy, 0, 0), crps_clogis(yy, loc, sc, lo, hi))
  lh <- loc + sc * runif(1, 3.2, 5); add("crps", c(14, loc, sc, lh, lh + sc * 2, yy + lh - loc, 0, 0), crps_tlogis(yy + lh - loc, loc, sc, lh, lh + sc * 2))
}
for (rep in 1:30) {
  df <- runif(1, 1.5, 15); loc <- rnorm(1); sc <- runif(1, 0.5, 2.5); lo <- loc + sc * runif(1, -2, 1.5); hi <- lo + sc * runif(1, 0.5, 4); yy <- rnorm(1, loc, 2 * sc)
  lm <- runif(1, 0, 0.3); um <- runif(1, 0, 0.3)
  add("crps", c(16, df, loc, sc, lo, hi, yy, lm, um), crps_gtct(yy, df, loc, sc, lo, hi, lm, um))
  add("crps", c(17, df, loc, sc, lo, hi, yy, 0, 0), crps_tt(yy, df, loc, sc, lo, hi))
  add("crps", c(18, df, loc, sc, lo, hi, yy, 0, 0), crps_ct(yy, df, loc, sc, lo, hi))
}
emit("scoringrules", "scoringRules", list(cases))
