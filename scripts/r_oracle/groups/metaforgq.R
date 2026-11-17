# metaforgq: metafor rma.uni with the generalized Q estimators GENQ and GENQM (method 11 and 14) with their weights, and confint(type = "genq") (lib/e/algo/stat/metaformore.e, metaforfit.e).
#   Cases as in metaforrma and metaforinf: fn "rma" (args = [method, test, weighted, level, tau2 fixed, intercept, k, p, nw, yi, vi, X, weights]) and fn "confint" (args = [6, the same]);
#   the "o" cases after them: 0 tau2, 1 se.tau2, 24 beta, 32 se, 40 zval, 48 pval, 56 ci.lb, 64 ci.ub; 136 tau2.lb, 137 tau2.ub, 138 I2.lb, 139 I2.ub, 140 H2.lb, 141 H2.ub.
suppressMessages(library(metafor))
cases <- list()
put <- function(v, i, x) { v[[as.character(i)]] <- if (is.null(x) || length(x) == 0) NA_real_ else as.numeric(x)[1]; v }
add_vec <- function(fn, args, vals, rel, abs = 1e-9) {
  idx <- as.integer(names(vals))
  cases[[length(cases) + 1]] <<- case(fn, args, vals[[1]], rel = rel, abs = abs)
  if (length(vals) > 1) for (j in 2:length(vals)) cases[[length(cases) + 1]] <<- case("o", idx[j], vals[[j]], rel = rel, abs = abs)
}
set.seed(20263232)
for (rep in 1:10) try({
  k <- sample(8:30, 1); p <- sample(1:3, 1)
  vi <- round(runif(k, 0.02, 0.4), 4)
  X <- if (p == 1) matrix(1, k, 1) else cbind(1, matrix(round(rnorm(k * (p - 1)), 3), k, p - 1))
  yi <- round(as.vector(X %*% rnorm(p, 0.2, 0.3)) + rnorm(k, 0, sqrt(vi + 0.05)), 4)
  w <- if (sample(2, 1) == 1) 1 / vi else round(runif(k, 0.5, 3), 3)
  for (mm in c("GENQ", "GENQM")) for (test in 0:2) {
    a <- list(yi = yi, vi = vi, weights = w, method = mm, test = c("z", "t", "knha")[test + 1])
    if (p > 1) a$mods <- X[, -1, drop = FALSE]
    r <- suppressWarnings(do.call(rma, a))
    args <- c(if (mm == "GENQ") 11 else 14, test, 1, 95, NA_real_, 1, k, p, k, yi, vi, as.vector(t(X)), w)
    v <- put(list(), 0, r$tau2); v <- put(v, 1, r$se.tau2)
    for (j in 1:p) { v <- put(v, 23 + j, r$beta[j]); v <- put(v, 31 + j, r$se[j]); v <- put(v, 39 + j, r$zval[j]); v <- put(v, 47 + j, r$pval[j]); v <- put(v, 55 + j, r$ci.lb[j]); v <- put(v, 63 + j, r$ci.ub[j]) }
    add_vec("rma", args, v[order(as.integer(names(v)))], 1e-8)
    if (test == 0) {
      ci <- tryCatch(suppressWarnings(confint(r)$random), error = function(e) NULL)
      if (!is.null(ci)) {
        v <- put(list(), 0, r$tau2)
        v <- put(v, 136, ci["tau^2", 2]); v <- put(v, 137, ci["tau^2", 3]); v <- put(v, 138, ci["I^2(%)", 2]); v <- put(v, 139, ci["I^2(%)", 3]); v <- put(v, 140, ci["H^2", 2]); v <- put(v, 141, ci["H^2", 3])
        add_vec("confint", c(6, args), v, 1e-7)
      }
    }
  }
}, silent = TRUE)
emit("metaforgq", "metafor", list(cases))
