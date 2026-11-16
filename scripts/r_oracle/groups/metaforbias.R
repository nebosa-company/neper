# metaforbias: metafor regtest, ranktest and fsn on a fixed-effect model.
# Cases with tied variances are skipped: ranktest then switches to the normal approximation with tie corrections, which is not ported.
#   "l1o" (method 0 FE 1 DL, dropped study, what 0 estimate 1 se 2 zval 3 pval 4 tau2 5 Q, k, yi, vi) is leave1out.
#   args: (test 0 regtest 1 ranktest 2 fsn, what (regtest 0 zval 1 pval 2 intercept 3 ci.lb 4 ci.ub 5 slope; ranktest 0 tau 1 pval), k, yi (k), vi (k))
suppressMessages(library(metafor))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-11)
set.seed(20262028)
for (rep in 1:30) {
  k <- sample(8:30, 1); vi <- round(runif(k, 0.02, 0.3), 4); yi <- round(rnorm(k, 0.3 + sample(c(0, 0.5, 1), 1) * sqrt(vi), 0.15), 4)
  if (anyDuplicated(vi)) next
  r <- rma(yi, vi, method = "FE"); g <- regtest(r); rk <- ranktest(r)
  vals <- c(g$zval, g$pval, g$est[1], g$ci.lb, g$ci.ub, coef(g$fit)[2])
  for (w in 0:5) add("bias", c(0, w, k, yi, vi), unname(vals[w + 1]))
  add("bias", c(1, 0, k, yi, vi), rk$tau); add("bias", c(1, 1, k, yi, vi), rk$pval)
  add("bias", c(2, 0, k, yi, vi), fsn(yi, vi)$fsnum)
}
for (rep in 1:20) {
  k <- sample(6:20, 1); vi <- round(runif(k, 0.02, 0.3), 4); yi <- round(rnorm(k, 0.3, sqrt(vi + 0.05)), 4); m <- sample(0:1, 1)
  l <- leave1out(rma(yi, vi, method = c("FE", "DL")[m + 1]))
  for (d in sample(k, 3)) { vals <- c(l$estimate[d], l$se[d], l$zval[d], l$pval[d], if (is.null(l$tau2)) 0 else l$tau2[d], l$Q[d]); for (w in 0:5) add("l1o", c(m, d - 1, w, k, yi, vi), vals[w + 1]) }
}
emit("metaforbias", "metafor", list(cases))
