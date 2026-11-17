# metaforfsn: metafor fsn, type Rosenthal with Fisher pooling and type General (lib/e/algo/stat/metaformore3.e).
#   Cases are fn fsn2 with args = [kind (0 Rosenthal, 4 General), alpha, target (NA none), pool (0 stouffer, 1 fisher), exact, mumiss, seed, maxint,
#   method, test, weighted, level (95), tau2 fixed or NA, intercept, k, p, nw, yi, vi, X]; want is out[0] (tau2) and the "o" cases after it are values at an index of the result vector:
#   136 fsnum, 137 pval, 138 target, 139 est, 140 tau2, 141 est.fsn, 142 tau2.fsn, 143 pval.fsn. set.seed(seed) comes immediately before fsn in R, and Neper seeds its stream with the same integer.
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
set.seed(20268181)
dat <- function(k, shift) {
  vi <- round(runif(k, 0.02, 0.4), 4)
  yi <- round(rnorm(k, shift, sqrt(vi + runif(1, 0, 0.1))), 4)
  list(yi = yi, vi = vi)
}
margs <- function(d, m, test, weighted, t2) c(m, test, weighted, 95, t2, 1, length(d$yi), 1, 0, d$yi, d$vi, rep(1, length(d$yi)))
pack <- function(f, r) {
  v <- put(list(), 0, r$tau2)
  v <- put(v, 136, f$fsnum); v <- put(v, 137, f$pval); v <- put(v, 138, f$target); v <- put(v, 139, f$est); v <- put(v, 140, f$tau2)
  v <- put(v, 141, f$est.fsn); v <- put(v, 142, f$tau2.fsn); v <- put(v, 143, f$pval.fsn)
  v
}
# Fisher pooling
for (rep in 1:10) try({
  k <- sample(6:25, 1); d <- dat(k, runif(1, 0.1, 0.5)); alpha <- c(0.05, 0.01, 0.1)[sample(3, 1)]
  r <- suppressWarnings(rma(d$yi, d$vi, method = "FE"))
  f <- suppressWarnings(fsn(d$yi, d$vi, type = "Rosenthal", alpha = alpha, pool = "fisher"))
  v <- put(put(put(list(), 0, r$tau2), 136, f$fsnum), 137, f$pval)
  add_vec("fsn2", c(0, alpha, NA_real_, 1, 0, 0, 1, 1e7, margs(d, 0, 0, 1, NA_real_)), v, 1e-9)
}, silent = TRUE)
# General
for (rep in 1:34) try({
  k <- sample(6:20, 1); d <- dat(k, runif(1, 0.15, 0.6)); alpha <- c(0.05, 0.01, 0.1)[sample(3, 1)]
  m <- sample(c(0, 1, 2, 7, 8, 9), 1); test <- sample(c(0, 0, 1, 2), 1)
  if (m == 0) test <- sample(0:1, 1)
  weighted <- sample(c(1, 1, 0), 1)
  t2 <- if (m != 0 && runif(1) < 0.15) 0.05 else NA_real_
  exact <- sample(c(0, 1), 1)
  mumiss <- if (runif(1) < 0.2) 0.1 else 0
  seed <- sample(1000:99999, 1)
  tg <- if (runif(1) < 0.4) NA_real_ else NA
  fit <- suppressWarnings(rma(d$yi, d$vi, method = mnames[m + 1], test = tnames[test + 1], weighted = weighted == 1, tau2 = if (is.na(t2)) NULL else t2))
  if (runif(1) < 0.4) tg <- as.numeric(fit$beta[1]) * runif(1, 0.2, 0.8) else tg <- NA_real_
  ddd <- list(d$yi, d$vi, type = "General", alpha = alpha, method = mnames[m + 1], exact = exact == 1, mumiss = mumiss, test = tnames[test + 1], weighted = weighted == 1)
  if (!is.na(t2)) ddd$tau2 <- t2
  if (!is.na(tg)) ddd$target <- tg
  set.seed(seed)
  f <- suppressWarnings(do.call(fsn, ddd))
  add_vec("fsn2", c(4, alpha, tg, 0, exact, mumiss, seed, 1e7, margs(d, m, test, weighted, t2)), pack(f, fit), 1e-9)
}, silent = TRUE)
emit("metaforfsn", "metafor", list(cases))
