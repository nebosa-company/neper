# metaforrma: metafor rma.uni with moderators, every estimator and test (lib/e/algo/stat/metaforfit.e).
#   A data case is fn "rma" with args = [method, test, weighted, level (95), tau2 fixed or NA, intercept, k, p, nw, yi (k), vi (k), X (k * p, row-major), weights (nw)];
#   method 0 FE 1 DL 2 HE 3 HS 4 HSk 5 SJ 6 PM 7 ML 8 REML 9 EB 10 PMM 11 GENQ 12 DLIT 13 SJIT; test 0 z 1 t 2 knha 3 adhoc. Its want is the result vector's first value (tau2); the
#   cases that follow it with fn "o" are the other values, args = [index into the vector]: 1 se.tau2 2 I2 3 H2 4 QE 5 QEp 6 QM 7 QMp 8 ddf 9..13 ll dev AIC BIC AICc (ML)
#   14..18 the same (REML) 19 R2 20 s2w 21 vt, beta 24+, se 32+, zval 40+, pval 48+, ci.lb 56+, ci.ub 64+, vb 72+ (row-major p x p).
suppressMessages(library(metafor))
cases <- list()
mnames <- c("FE", "DL", "HE", "HS", "HSk", "SJ", "PM", "ML", "REML", "EB", "PMM", "GENQ", "DLIT", "SJIT")
add_vec <- function(fn, args, vals, rel, abs = 1e-10) {
  # vals: named list index -> value, in increasing index order
  idx <- as.integer(names(vals))
  cases[[length(cases) + 1]] <<- case(fn, args, vals[[1]], rel = rel, abs = abs)
  if (length(vals) > 1) for (j in 2:length(vals)) cases[[length(cases) + 1]] <<- case("o", idx[j], vals[[j]], rel = rel, abs = abs)
}
fit_vals <- function(r, p, k, fixed = FALSE) {
  fs <- r$fit.stats
  v <- list()
  put <- function(i, x) v[[as.character(i)]] <<- if (is.null(x)) NA_real_ else as.numeric(x)
  put(0, r$tau2); if (!fixed) put(1, r$se.tau2)
  put(2, r$I2); put(3, r$H2); put(4, r$QE); put(5, r$QEp); put(6, r$QM); put(7, r$QMp)
  put(8, if (is.na(r$ddf)) NA_real_ else r$ddf)
  for (j in 1:5) { put(8 + j, fs[j, "ML"]); put(13 + j, fs[j, "REML"]) }
  put(19, r$R2); put(20, r$s2w); put(21, r$vt)
  for (a in 1:p) {
    put(23 + a, r$beta[a]); put(31 + a, r$se[a]); put(39 + a, r$zval[a]); put(47 + a, r$pval[a]); put(55 + a, r$ci.lb[a]); put(63 + a, r$ci.ub[a])
    for (b in 1:p) put(72 + (a - 1) * p + b - 1, r$vb[a, b])
  }
  v[order(as.integer(names(v)))]
}
rel_of <- function(m) 1e-9
set.seed(20262727)
dat <- function(k, p, intercept = TRUE) {
  vi <- round(runif(k, 0.02, 0.4), 4)
  X <- if (p == 1 && intercept) matrix(1, k, 1) else {
    cols <- if (intercept) p - 1 else p
    M <- sapply(seq_len(cols), function(j) if (j %% 2 == 1) round(rnorm(k), 3) else rbinom(k, 1, 0.5))
    M <- matrix(M, k, cols)
    if (intercept) cbind(1, M) else M
  }
  b <- rnorm(ncol(X), 0.2, 0.3)
  yi <- round(as.vector(X %*% b) + rnorm(k, 0, sqrt(vi + runif(1, 0, 0.15))), 4)
  list(yi = yi, vi = vi, X = X)
}
fitr <- function(d, m, test, weights = NULL, intercept = TRUE, tau2 = NULL, weighted = TRUE) {
  p <- ncol(d$X)
  mods <- if (intercept) { if (p == 1) NULL else d$X[, -1, drop = FALSE] } else d$X
  a <- list(yi = d$yi, vi = d$vi, intercept = intercept, method = mnames[m + 1], test = c("z", "t", "knha", "adhoc")[test + 1], weighted = weighted)
  if (!is.null(mods)) a$mods <- mods
  if (!is.null(weights)) a$weights <- weights
  if (!is.null(tau2)) a$tau2 <- tau2
  tryCatch(suppressWarnings(do.call(rma, a)), error = function(e) NULL)
}
do_case <- function(d, m, test, weights = NULL, intercept = TRUE, tau2 = NULL, weighted = TRUE) {
  r <- fitr(d, m, test, weights, intercept, tau2, weighted)
  if (is.null(r)) return(invisible())
  k <- length(d$yi); p <- ncol(d$X)
  fixed <- !is.null(tau2) && m != 0
  args <- c(m, test, as.integer(weighted), 95, if (fixed) tau2 else NA_real_, as.integer(intercept), k, p, length(weights), d$yi, d$vi, as.vector(t(d$X)), weights)
  add_vec("rma", args, fit_vals(r, p, k, fixed), rel_of(m))
}
for (rep in 1:14) {
  k <- sample(6:30, 1); p <- sample(1:4, 1)
  d <- dat(k, p)
  for (m in c(0:10, 12, 13)) do_case(d, m, 0)
  tt <- sample(1:3, 3, replace = TRUE); mm <- sample(c(1, 2, 5, 6, 7, 8, 9), 3)
  for (j in 1:3) do_case(d, mm[j], tt[j])
}
for (rep in 1:3) {
  k <- sample(8:25, 1); p <- sample(2:3, 1)
  d <- dat(k, p, FALSE)
  for (m in c(0, 1, 2, 7, 8)) do_case(d, m, sample(0:2, 1), intercept = FALSE)
}
for (rep in 1:3) {
  k <- sample(8:25, 1); p <- sample(1:3, 1)
  d <- dat(k, p)
  w <- round(runif(k, 0.5, 3), 3)
  do_case(d, 11, 0, weights = w); do_case(d, 11, 2, weights = w); do_case(d, 8, 0, weights = w); do_case(d, 1, 2, weights = w)
  do_case(d, 8, 0, weighted = FALSE); do_case(d, 1, 2, weighted = FALSE); do_case(d, 0, 0, weighted = FALSE)
  do_case(d, 8, 0, tau2 = 0.1); do_case(d, 1, 1, tau2 = 0.05); do_case(d, 7, 0, tau2 = 0.2); do_case(d, 6, 0, tau2 = 0.03)
}
emit("metaforrma", "metafor", list(cases))
