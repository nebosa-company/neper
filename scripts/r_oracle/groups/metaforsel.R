# metaforsel: metafor permutest, regtest, ranktest, trimfill, fsn and profile on a fitted rma.uni (lib/e/algo/stat/metaformore2.e).
#   Cases are fn <name> with args = [options, model, extra] (see lib/e/algo/stat/metaforrun.e): want is out[0] (tau2) and the "o" cases after it are values at an index of the result vector.
#   permutest: 136 + a pval of coefficient a, 144 the omnibus p-value; regtest 136 zval 137 pval 138 ddf 139 est 140 ci.lb 141 ci.ub; ranktest 136 tau 137 p-value; fsn 136 fsnum 137 pval 138 target;
#   trimfill 136 k0 137 se.k0 138 p.k0 139 side (0 left 1 right) and the fit of the final model at 0.. (tau2 0, I2 2, H2 3, QE 4, beta 24, se 32, zval 40, pval 48, ci.lb 56, ci.ub 64); profile 136 + 16 i: ll beta ci.lb ci.ub I2 H2.
suppressMessages(library(metafor))
cases <- list()
mnames <- c("FE", "DL", "HE", "HS", "HSk", "SJ", "PM", "ML", "REML", "EB", "PMM", "GENQ", "DLIT", "SJIT")
tnames <- c("z", "t", "knha", "adhoc")
add_vec <- function(fn, args, vals, rel, abs = 1e-9) {
  idx <- as.integer(names(vals))
  cases[[length(cases) + 1]] <<- case(fn, args, vals[[1]], rel = rel, abs = abs)
  if (length(vals) > 1) for (j in 2:length(vals)) cases[[length(cases) + 1]] <<- case("o", idx[j], vals[[j]], rel = rel, abs = abs)
}
put <- function(v, i, x) { v[[as.character(i)]] <- if (is.null(x) || length(x) == 0) NA_real_ else as.numeric(x)[1]; v }
set.seed(20262929)
dat <- function(k, p, bin = FALSE) {
  vi <- round(runif(k, 0.02, 0.4), 4)
  X <- if (p == 1) matrix(1, k, 1) else {
    M <- sapply(seq_len(p - 1), function(j) if (bin || j %% 2 == 0) rbinom(k, 1, 0.5) else round(rnorm(k), 3))
    cbind(1, matrix(M, k, p - 1))
  }
  b <- rnorm(ncol(X), 0.2, 0.3)
  yi <- round(as.vector(X %*% b) + rnorm(k, 0, sqrt(vi + runif(1, 0, 0.15))), 4)
  list(yi = yi, vi = vi, X = X)
}
fitr <- function(d, m, test) {
  p <- ncol(d$X)
  a <- list(yi = d$yi, vi = d$vi, method = mnames[m + 1], test = tnames[test + 1])
  if (p > 1) a$mods <- d$X[, -1, drop = FALSE]
  suppressWarnings(do.call(rma, a))
}
margs <- function(d, m, test) c(m, test, 1, 95, NA_real_, 1, length(d$yi), ncol(d$X), 0, d$yi, d$vi, as.vector(t(d$X)))
# permutest
for (rep in 1:5) try({
  k <- sample(5:9, 1); d <- dat(k, 1)
  for (m in c(1, 8)) {
    test <- sample(c(0, 1, 2), 1)
    r <- fitr(d, m, test)
    pe <- suppressWarnings(permutest(r, exact = TRUE, progbar = FALSE))
    add_vec("permutest", c(1, 100, 1, margs(d, m, test)), put(put(put(list(), 0, r$tau2), 136, pe$pval), 144, pe$QMp), 1e-9)
  }
}, silent = TRUE)
for (rep in 1:4) try({
  k <- sample(6:9, 1); d <- dat(k, 2, TRUE)
  m <- sample(c(1, 8), 1); test <- sample(c(0, 2), 1)
  r <- fitr(d, m, test)
  pe <- suppressWarnings(permutest(r, exact = TRUE, progbar = FALSE))
  v <- put(put(put(put(list(), 0, r$tau2), 136, pe$pval[1]), 137, pe$pval[2]), 144, pe$QMp)
  add_vec("permutest", c(1, 100, 1, margs(d, m, test)), v, 1e-9)
}, silent = TRUE)
for (rep in 1:5) try({
  k <- sample(10:16, 1); p <- sample(1:3, 1); d <- dat(k, p)
  m <- sample(c(1, 7, 8), 1); test <- sample(0:2, 1)
  r <- fitr(d, m, test)
  seed <- sample(1000:99999, 1)
  pe <- suppressWarnings(permutest(r, exact = FALSE, iter = 200, seed = seed, progbar = FALSE))
  v <- put(list(), 0, r$tau2); for (a in 1:p) v <- put(v, 135 + a, pe$pval[a]); v <- put(v, 144, pe$QMp)
  add_vec("permutest", c(0, 200, seed, margs(d, m, test)), v, 1e-9)
}, silent = TRUE)
# regtest, ranktest, fsn
for (rep in 1:10) try({
  k <- sample(8:25, 1); p <- sample(1:3, 1); d <- dat(k, p)
  m <- sample(c(0, 1, 7, 8, 9), 1); test <- sample(0:2, 1)
  if (m == 0) test <- sample(0:1, 1)
  r <- fitr(d, m, test)
  ni <- sample(20:200, k, replace = TRUE)
  for (pred in 0:5) for (mod in 0:1) {
    if (mod == 1 && pred != 0) next
    rt <- tryCatch(suppressWarnings(regtest(r, predictor = c("sei", "vi", "ni", "ninv", "sqrtni", "sqrtninv")[pred + 1], model = c("rma", "lm")[mod + 1], ni = ni)), error = function(e) NULL)
    if (is.null(rt)) next
    v <- put(list(), 0, r$tau2)
    v <- put(v, 136, rt$zval); v <- put(v, 137, rt$pval); v <- put(v, 138, rt$ddf); v <- put(v, 139, rt$est); v <- put(v, 140, rt$ci.lb); v <- put(v, 141, rt$ci.ub)
    add_vec("regtest", c(pred, mod, margs(d, m, test), ni), v, 1e-8)
  }
}, silent = TRUE)
for (rep in 1:8) try({
  k <- sample(6:30, 1); d <- dat(k, 1)
  r <- fitr(d, 1, 0)
  rk <- ranktest(r)
  add_vec("ranktest", margs(d, 1, 0), put(put(put(list(), 0, r$tau2), 136, rk$tau), 137, rk$pval), 1e-9)
  d$yi <- d$yi + 0.8 * sqrt(d$vi)
  rk <- ranktest(d$yi, d$vi)
  r <- fitr(d, 1, 0)
  add_vec("ranktest", margs(d, 1, 0), put(put(put(list(), 0, r$tau2), 136, rk$tau), 137, rk$pval), 1e-9)
}, silent = TRUE)
for (rep in 1:12) try({
  k <- sample(6:25, 1); d <- dat(k, 1)
  ty <- sample(0:3, 1); alpha <- c(0.05, 0.01, 0.1)[sample(3, 1)]
  d$yi <- d$yi + runif(1, 0, 0.5)
  r <- fitr(d, 0, 0)
  f <- suppressWarnings(fsn(d$yi, d$vi, type = c("Rosenthal", "Orwin", "Rosenberg", "Binomial")[ty + 1], alpha = alpha))
  tg <- f$target
  add_vec("fsn", c(ty, alpha, NA_real_, margs(d, 0, 0)), put(put(put(put(list(), 0, r$tau2), 136, f$fsnum), 137, f$pval), 138, tg), 1e-9)
}, silent = TRUE)
# trimfill
for (rep in 1:25) try({
  k <- sample(8:30, 1); d <- dat(k, 1)
  d$yi <- round(d$yi + 1.2 * sqrt(d$vi) * sample(c(-1, 1), 1), 4)
  m <- sample(c(0, 1, 7, 8), 1); test <- sample(0:2, 1)
  if (m == 0) test <- 0
  r <- fitr(d, m, test)
  est <- sample(0:2, 1)
  side <- sample(c(-1, 0, 1), 1)
  tf <- tryCatch(suppressWarnings(trimfill(r, estimator = c("L0", "R0", "Q0")[est + 1], side = if (side < 0) NULL else c("left", "right")[side + 1])), error = function(e) NULL)
  if (is.null(tf)) next
  v <- put(list(), 0, tf$tau2)
  v <- put(v, 2, tf$I2); v <- put(v, 3, tf$H2); v <- put(v, 4, tf$QE); v <- put(v, 24, tf$beta[1]); v <- put(v, 32, tf$se); v <- put(v, 40, tf$zval); v <- put(v, 48, tf$pval); v <- put(v, 56, tf$ci.lb); v <- put(v, 64, tf$ci.ub)
  v <- put(v, 136, tf$k0); v <- put(v, 137, tf$se.k0); v <- put(v, 138, tf$p.k0); v <- put(v, 139, if (tf$side == "right") 1 else 0)
  add_vec("trimfill", c(est, side, margs(d, m, test)), v, 1e-9)
}, silent = TRUE)
# profile
for (rep in 1:6) try({
  k <- sample(6:20, 1); p <- sample(1:3, 1); d <- dat(k, p)
  m <- sample(c(7, 8), 1)
  r <- fitr(d, m, 0)
  xl <- c(0, 0.6)
  pr <- tryCatch(suppressWarnings(profile(r, xlim = xl, steps = 5, plot = FALSE, progbar = FALSE)), error = function(e) NULL)
  if (is.null(pr)) next
  v <- put(list(), 0, r$tau2)
  for (i in 1:5) {
    b <- 136 + 16 * (i - 1)
    v <- put(v, b, pr$ll[i]); v <- put(v, b + 1, pr$beta[i, 1])
  }
  add_vec("profile", c(5, pr$tau2, margs(d, m, 0)), v, 1e-9)
}, silent = TRUE)
emit("metaforsel", "metafor", list(cases))
