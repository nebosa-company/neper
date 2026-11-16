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
for (rep in 1:25) {
  n <- sample(5:40, 1); dat <- round(rnorm(n, 0.3, 1.2), 4); yy <- rnorm(1, 0.3, 1.5); w <- round(runif(n, 0.1, 2), 3); bw <- runif(1, 0.2, 1)
  add("crpsw", c(yy, n, dat, w), crps_sample(yy, dat, w = w, show_messages = FALSE))
  add("crpskde", c(yy, n, dat, 0), crps_sample(yy, dat, method = "kde", show_messages = FALSE))
  add("crpskde", c(yy, n, dat, bw), crps_sample(yy, dat, method = "kde", bw = bw, show_messages = FALSE))
}
for (rep in 1:30) {
  sz <- runif(1, 0.5, 12); pr <- runif(1, 0.15, 0.9); yy <- sample(0:15, 1)
  v <- tryCatch(crps_nbinom(yy, sz, pr), error = function(e) NA); if (is.finite(v)) add("crps", c(19, sz, pr, 0, 0, yy), v)
}
for (rep in 1:25) {
  yy <- rnorm(1, 0.5, 2); yp <- abs(rnorm(1, 1, 1.5)) + 0.05
  k <- sample(2:4, 1); mm <- rnorm(k); ss <- runif(k, 0.3, 2); ww <- runif(k, 0.1, 1)
  add("crpsmix", c(yy, k, mm, ss, ww), crps_mixnorm(yy, matrix(mm, 1), matrix(ss, 1), matrix(ww, 1)))
  shp <- runif(1, -0.45, 0.8); lc <- rnorm(1); sc <- runif(1, 0.5, 2.5)
  add("crps", c(21, shp, lc, sc, 0, yy), crps_gev(yy, shp, lc, sc)); add("crps", c(21, 1e-14, lc, sc, 0, yy), crps_gev(yy, 1e-14, lc, sc))
  ms <- runif(1, 0, 0.5); add("crps", c(22, shp, lc, sc, ms, yp + lc), crps_gpd(yp + lc, shp, lc, sc, ms)); add("crps", c(22, 0, lc, sc, ms, yp + lc), crps_gpd(yp + lc, 0, lc, sc, ms))
  sl <- runif(1, 0.1, 0.9); add("crps", c(23, lc, sl, 0, 0, yp), crps_llapl(yp, lc, sl)); add("crps", c(24, lc, sl, 0, 0, yp), crps_llogis(yp, lc, sl))
  s1 <- runif(1, 0.3, 2); s2 <- runif(1, 0.3, 2); add("crps", c(25, s1, s2, lc, 0, yy), crps_2pexp(yy, s1, s2, lc)); add("crps", c(26, s1, s2, lc, 0, yy), crps_2pnorm(yy, s1, s2, lc))
  add("crps", c(27, lc, sc, ms, 0, yy), crps_expM(yy, lc, sc, ms))
}
for (rep in 1:25) {
  yy <- rnorm(1, 0.5, 2); yp <- abs(rnorm(1, 1, 1.5)) + 0.05; lc <- rnorm(1); sc <- runif(1, 0.5, 2.5); yb <- runif(1, 0.05, 0.95)
  a1 <- runif(1, 0.5, 5); b1 <- runif(1, 0.5, 5); lo <- runif(1, -2, 0); hi <- lo + runif(1, 0.5, 4); yl <- lo + (hi - lo) * yb
  add("crps", c(28, a1, b1, 0, 1, yb), crps_beta(yb, a1, b1)); add("crps", c(28, a1, b1, lo, hi, yl), crps_beta(yl, a1, b1, lo, hi))
  add("logs", c(28, a1, b1, lo, hi, yl), logs_beta(yl, a1, b1, lo, hi)); add("dss", c(28, a1, b1, lo, hi, yl), dss_beta(yl, a1, b1, lo, hi))
  mh <- sample(3:12, 1); nh <- sample(3:12, 1); kh <- sample(2:min(mh + nh, 10), 1); yh <- sample(0:kh, 1)
  add("crps", c(29, mh, nh, kh, 0, yh), crps_hyper(yh, mh, nh, kh)); add("logs", c(29, mh, nh, kh, 0, min(yh, mh)), logs_hyper(min(yh, mh), mh, nh, kh))
  sz <- runif(1, 0.5, 10); pr <- runif(1, 0.15, 0.9); yn <- sample(0:12, 1)
  add("logs", c(30, sz, pr, 0, 0, yn), logs_nbinom(yn, sz, pr)); add("dss", c(30, sz, pr, 0, 0, yn), dss_nbinom(yn, sz, pr))
  df <- runif(1, 2.5, 15); add("logs", c(31, df, lc, sc, 0, yy), logs_t(yy, df, lc, sc)); add("dss", c(31, df, lc, sc, 0, yy), dss_t(yy, df, lc, sc))
  add("dss", c(32, lc, sc * sc, 0, 0, yy), dss_moments(yy, lc, sc * sc))
  tl <- lc - runif(1, 0, 3); tu <- lc + runif(1, 0.5, 3); yt <- runif(1, tl, tu); add("logs", c(33, lc, sc, tl, tu, yt), logs_tnorm(yt, lc, sc, tl, tu))
  shp <- runif(1, -0.4, 0.45); yg <- lc + sc * runif(1, 0.1, 2) / (1 + abs(shp))
  add("logs", c(21, shp, lc, sc, 0, yg), logs_gev(yg, shp, lc, sc)); add("dss", c(21, shp, lc, sc, 0, yg), dss_gev(yg, shp, lc, sc)); add("dss", c(21, 1e-14, lc, sc, 0, yg), dss_gev(yg, 1e-14, lc, sc))
  add("logs", c(22, shp, lc, sc, 0, yp + lc), logs_gpd(yp + lc, shp, lc, sc)); add("dss", c(22, shp, lc, sc, 0, yp + lc), dss_gpd(yp + lc, shp, lc, sc))
  sl <- runif(1, 0.05, 0.45); add("logs", c(23, lc, sl, 0, 0, yp), logs_llapl(yp, lc, sl)); add("dss", c(23, lc, sl, 0, 0, yp), dss_llapl(yp, lc, sl))
  add("logs", c(24, lc, sl, 0, 0, yp), logs_llogis(yp, lc, sl)); add("dss", c(24, lc, sl, 0, 0, yp), dss_llogis(yp, lc, sl))
  s1 <- runif(1, 0.3, 2); s2 <- runif(1, 0.3, 2); add("logs", c(25, s1, s2, lc, 0, yy), logs_2pexp(yy, s1, s2, lc)); add("logs", c(26, s1, s2, lc, 0, yy), logs_2pnorm(yy, s1, s2, lc))
  k <- sample(2:4, 1); mm <- rnorm(k); ss <- runif(k, 0.3, 2); ww <- runif(k, 0.1, 1)
  add("logsmix", c(yy, k, mm, ss, ww), logs_mixnorm(yy, matrix(mm, 1), matrix(ss, 1), matrix(ww, 1))); add("dssmix", c(yy, k, mm, ss, ww), dss_mixnorm(yy, matrix(mm, 1), matrix(ss, 1), matrix(ww, 1)))
}
for (rep in 1:25) {
  yy <- rnorm(1, 0.3, 1.5); n <- sample(8:40, 1); dat <- round(rnorm(n, 0.3, 1.2), 4); tc <- runif(1, 0.3, 0.95); xl <- rnorm(1, -1); xu <- xl + runif(1, 0.5, 3)
  add("ex", c(0, yy, tc, xl, xu, 0), ints_quantiles(yy, xl, xu, tc)); add("exs", c(1, yy, tc, n, dat), ints_sample(yy, dat, tc, show_messages = FALSE))
  mn <- rnorm(1); vr <- runif(1, 0.5, 3); sk <- rnorm(1); add("ex", c(2, yy, mn, vr, sk, 0), ess_moments(yy, mn, vr, sk))
  df <- runif(1, 1.5, 12); loc <- rnorm(1); sc <- runif(1, 0.5, 2.5)
  for (fm in 0:2) {
    gg <- switch(fm + 1, gradcrps_norm(yy, loc, sc), gradcrps_logis(yy, loc, sc), gradcrps_t(yy, df, loc, sc)); hh <- switch(fm + 1, hesscrps_norm(yy, loc, sc), hesscrps_logis(yy, loc, sc), hesscrps_t(yy, df, loc, sc))
    add("ex", c(3, yy, fm, df, loc, sc, 0), gg[1, 1]); add("ex", c(3, yy, fm, df, loc, sc, 1), gg[1, 2])
    for (pp in 0:2) add("ex", c(4, yy, fm, df, loc, sc, pp), hh[1, pp + 1])
  }
  lo <- rnorm(1, -1, 0.5); hi <- lo + runif(1, 1, 3); yc <- rnorm(1, 0.3, 1.5)
  add("exs", c(5, yc, lo, n, dat, hi, 1), clogs_sample(yc, dat, lo, hi, cens = TRUE)); add("exs", c(5, yc, lo, n, dat, hi, 0), clogs_sample(yc, dat, lo, hi, cens = FALSE))
  d <- sample(2:4, 1); m <- sample(4:12, 1); X <- matrix(rnorm(d * m), d, m); yv <- rnorm(d)
  add("exs", c(6, d, m, 0, as.vector(X), yv), mmds_sample(yv, X))
}
for (rep in 1:25) {
  n <- sample(8:40, 1); dat <- round(rnorm(n, 0.3, 1.2), 4); yy <- rnorm(1, 0.3, 1.5); lo <- rnorm(1, -0.5, 0.5); hi <- lo + runif(1, 0.5, 3); mu <- rnorm(1); sg <- runif(1, 0.5, 2)
  add("ow1", c(99, yy, lo, hi, mu, sg, n, dat), owcrps_sample(yy, dat, a = lo, b = hi, show_messages = FALSE)); add("tw1", c(99, yy, lo, hi, mu, sg, n, dat), twcrps_sample(yy, dat, a = lo, b = hi, show_messages = FALSE))
  nm <- c("norm_cdf", "norm_surv", "norm_pdf", "logis_cdf", "logis_surv", "logis_pdf"); id <- sample(0:5, 1)
  add("ow1", c(id, yy, lo, hi, mu, sg, n, dat), owcrps_sample(yy, dat, weight_func = get_weight_func(nm[id + 1], mu, sg), show_messages = FALSE))
  add("tw1", c(id, yy, lo, hi, mu, sg, n, dat), twcrps_sample(yy, dat, chain_func = get_weight_func(nm[id + 1], mu, sg, weight = FALSE), show_messages = FALSE))
  d <- sample(2:4, 1); m <- sample(6:20, 1); X <- matrix(rnorm(d * m, 0.2, 1.2), d, m); yv <- rnorm(d, 0.2, 1.2); lo <- -0.8; hi <- 1.5; pp <- runif(1, 0.3, 1)
  for (tw in 0:1) {
    add("mv", c(0, tw, d, m, lo, hi, pp, as.vector(X), yv), if (tw == 1) twes_sample(yv, X, lo, hi) else owes_sample(yv, X, lo, hi))
    add("mv", c(1, tw, d, m, lo, hi, pp, as.vector(X), yv), if (tw == 1) twmmds_sample(yv, X, lo, hi) else owmmds_sample(yv, X, lo, hi))
    add("mv", c(2, tw, d, m, lo, hi, pp, as.vector(X), yv), if (tw == 1) twvs_sample(yv, X, lo, hi, p = pp) else owvs_sample(yv, X, lo, hi, p = pp))
  }
}
for (rep in 1:25) {
  loc <- rnorm(1); sc <- runif(1, 0.5, 2.5); lo <- loc - sc * runif(1, 0.2, 2); hi <- loc + sc * runif(1, 0.2, 3); yin <- runif(1, lo, hi); df <- runif(1, 1.5, 12)
  add("logs", c(34, loc, sc, 0, 0, yin + 0.3), logs_exp2(yin + 0.3, loc, sc))
  add("logs", c(35, loc, sc, lo, hi, yin), logs_tlogis(yin, loc, sc, lo, hi)); add("logs", c(36, df, loc, sc, 0, yin, lo, hi), logs_tt(yin, df, loc, sc, lo, hi))
}
emit("scoringrules", "scoringRules", list(cases))
