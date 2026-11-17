# metaforinf: metafor confint, predict, blup, rstandard, influence, leave1out and cumul on a fitted rma.uni (lib/e/algo/stat/metaformore.e).
#   A case is fn <name> with args = [options, model, extra] (see lib/e/algo/stat/metaforrun.e); its want is out[0] (tau2); the cases after it, fn "o", are values at an index of the result vector:
#   136 + 16 i + j is value j of study (or row) i: rstandard 0..2 marginal resid, se, z, 3..5 conditional, 6 hat, 7 weight %; influence 0 rstudent 1 dffits 2 cook.d 3 cov.r 4 tau2.del 5 QE.del 6 hat 7 weight
#   8 + a dfbetas; blup 8 pred 9 se 10 pi.lb 11 pi.ub; predict 0 pred 1 se 2 ci.lb 3 ci.ub 4 pi.lb 5 pi.ub; leave1out and cumul 0 beta 1 se 2 zval 3 pval 4 ci.lb 5 ci.ub 6 QE 7 QEp 8 tau2 9 I2 10 H2.
#   confint: 136 tau2.lb 137 tau2.ub 138 I2.lb 139 I2.ub 140 H2.lb 141 H2.ub 142 tau.lb 143 tau.ub.
suppressMessages(library(metafor))
cases <- list()
mnames <- c("FE", "DL", "HE", "HS", "HSk", "SJ", "PM", "ML", "REML", "EB", "PMM", "GENQ", "DLIT", "SJIT")
tnames <- c("z", "t", "knha", "adhoc")
add_vec <- function(fn, args, vals, rel, abs = 1e-9) {
  idx <- as.integer(names(vals))
  cases[[length(cases) + 1]] <<- case(fn, args, vals[[1]], rel = rel, abs = abs)
  if (length(vals) > 1) for (j in 2:length(vals)) cases[[length(cases) + 1]] <<- case("o", idx[j], vals[[j]], rel = rel, abs = abs)
}
set.seed(20262828)
dat <- function(k, p) {
  vi <- round(runif(k, 0.02, 0.4), 4)
  X <- if (p == 1) matrix(1, k, 1) else {
    M <- sapply(seq_len(p - 1), function(j) if (j %% 2 == 1) round(rnorm(k), 3) else rbinom(k, 1, 0.5))
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
put <- function(v, i, x) { v[[as.character(i)]] <- as.numeric(x); v }
rows <- function(v, base, j, x) { for (i in seq_along(x)) v <- put(v, base + 16 * (i - 1) + j, x[i]); v }
ci_run <- function(d, m, test, type, code) {
  r <- fitr(d, m, test)
  ci <- tryCatch(suppressWarnings(confint(r, type = type)$random), error = function(e) NULL)
  if (is.null(ci)) return(invisible())
  v <- put(list(), 0, r$tau2)
  v <- put(v, 136, ci["tau^2", 2]); v <- put(v, 137, ci["tau^2", 3]); v <- put(v, 138, ci["I^2(%)", 2]); v <- put(v, 139, ci["I^2(%)", 3])
  v <- put(v, 140, ci["H^2", 2]); v <- put(v, 141, ci["H^2", 3]); v <- put(v, 142, ci["tau", 2]); v <- put(v, 143, ci["tau", 3])
  add_vec("confint", c(code, margs(d, m, test)), v, 1e-8)
}
for (rep in 1:10) try({
  k <- sample(6:25, 1); p <- sample(1:3, 1)
  d <- dat(k, p)
  for (m in c(1, 2, 8, 7, 6, 9)) {
    ci_run(d, m, 0, "QP", 0)
    ci_run(d, m, 0, "PL", 1)
  }
  if (p == 1) { ci_run(d, 8, 0, "HT", 2); ci_run(d, 8, 0, "Wald", 3); ci_run(d, 7, 0, "Wald.log", 4); ci_run(d, 8, 2, "Wald.sqrt", 5) }
  ci_run(d, 1, 2, "QP", 0)
}, silent = TRUE)
for (rep in 1:8) try({
  k <- sample(5:14, 1); p <- sample(1:3, 1)
  d <- dat(k, p)
  m <- sample(c(1, 2, 7, 8), 1); test <- sample(0:3, 1)
  r <- fitr(d, m, test)
  pt <- c(0, 1, 2, 3)[sample(4, 1)]
  newm <- if (p > 1) matrix(round(rnorm(3 * (p - 1)), 3), 3, p - 1) else NULL
  Xn <- if (p > 1) cbind(1, newm) else matrix(1, 1, 1)
  pi_type <- c("default", "simple", "Riley", "t")[pt + 1]
  adj <- sample(0:1, 1)
  pr <- if (p > 1) predict(r, newmods = newm, pi.type = pi_type, adjust = adj == 1) else predict(r, pi.type = pi_type, adjust = adj == 1)
  v <- put(list(), 0, r$tau2)
  for (j in 0:5) v <- rows(v, 136, j, as.numeric(c(pr$pred, pr$se, pr$ci.lb, pr$ci.ub, pr$pi.lb, pr$pi.ub)[(j * nrow(Xn) + 1):((j + 1) * nrow(Xn))]))
  add_vec("predict", c(nrow(Xn), pt, adj, margs(d, m, test), as.vector(t(Xn))), v, 1e-9)
  bl <- blup(r)
  v <- put(list(), 0, r$tau2)
  for (j in 0:3) v <- rows(v, 136, 8 + j, c(bl$pred, bl$se, bl$pi.lb, bl$pi.ub)[(j * k + 1):((j + 1) * k)])
  add_vec("blup", margs(d, m, test), v, 1e-9)
  rs <- rstandard(r); rc <- rstandard(r, type = "conditional"); h <- hatvalues(r); w <- weights(r)
  v <- put(list(), 0, r$tau2)
  v <- rows(v, 136, 0, rs$resid); v <- rows(v, 136, 1, rs$se); v <- rows(v, 136, 2, rs$z)
  v <- rows(v, 136, 3, rc$resid); v <- rows(v, 136, 4, rc$se); v <- rows(v, 136, 5, rc$z); v <- rows(v, 136, 6, h); v <- rows(v, 136, 7, w)
  add_vec("rstandard", margs(d, m, test), v, 1e-9)
}, silent = TRUE)
for (rep in 1:7) try({
  k <- sample(6:12, 1); p <- sample(1:3, 1)
  d <- dat(k, p)
  m <- sample(c(1, 2, 7, 8, 9), 1); test <- sample(c(0, 2), 1)
  r <- fitr(d, m, test)
  inf <- tryCatch(suppressWarnings(influence(r)), error = function(e) NULL)
  if (is.null(inf)) next
  v <- put(list(), 0, r$tau2)
  for (j in 0:7) v <- rows(v, 136, j, inf$inf[[j + 1]])
  for (a in 1:p) v <- rows(v, 136, 7 + a, inf$dfbs[[a]])
  add_vec("influence", margs(d, m, test), v, 1e-8)
}, silent = TRUE)
for (rep in 1:8) try({
  k <- sample(6:20, 1)
  d <- dat(k, 1)
  m <- sample(c(0, 1, 2, 7, 8, 9, 6), 1); test <- sample(0:3, 1)
  if (m == 0) test <- sample(0:1, 1)
  r <- fitr(d, m, test)
  l <- leave1out(r)
  v <- put(list(), 0, r$tau2)
  cols <- list(l$estimate, l$se, l$zval, l$pval, l$ci.lb, l$ci.ub, l$Q, l$Qp, l$tau2, l$I2, l$H2)
  for (j in 0:10) v <- rows(v, 136, j, cols[[j + 1]])
  add_vec("leave1out", margs(d, m, test), v, 1e-8)
  cu <- cumul(r)
  cols <- list(cu$estimate, cu$se, cu$zval, cu$pval, cu$ci.lb, cu$ci.ub, cu$Q, cu$Qp, cu$tau2, cu$I2, cu$H2)
  v <- put(list(), 0, r$tau2)
  for (j in 0:10) v <- rows(v, 136, j, cols[[j + 1]])
  add_vec("cumul", margs(d, m, test), v, 1e-8)
}, silent = TRUE)
emit("metaforinf", "metafor", list(cases))
