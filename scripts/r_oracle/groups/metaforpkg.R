# metaforpkg: metafor rma.uni intercept-only models.
#   args: (method 0 FE 1 DL 2 HE 3 HS 4 SJ 5 PM 6 ML 7 REML, what 0 beta 1 se 2 tau2 3 I2 4 H2 5 QE 6 QEp 7 zval 8 pval 9 ci.lb 10 ci.ub, k, yi (k), vi (k)).
#   DL, HE, HS, SJ and FE are closed forms (rel 1e-9); PM, ML and REML are iterative in metafor (threshold 1e-5) and here exact maxima, so they are compared at rel 1e-2 and abs 1e-2: when the likelihood is nearly flat at zero metafor stops at a small positive tau2 (up to about 0.008 here) where the exact maximum is the boundary.
suppressMessages(library(metafor))
cases <- list()
add <- function(fn, args, want, rel) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = if (rel > 1e-6) 1e-2 else 1e-8)
ms <- c("FE", "DL", "HE", "HS", "SJ", "PM", "ML", "REML")
set.seed(20262026)
for (rep in 1:30) {
  k <- sample(5:25, 1); vi <- round(runif(k, 0.02, 0.3), 4); yi <- round(rnorm(k, 0.3, sqrt(vi + 0.05)), 4)
  for (m in 0:7) {
    r <- suppressWarnings(rma(yi, vi, method = ms[m + 1]))
    vals <- c(r$beta[1], r$se, r$tau2, r$I2, r$H2, r$QE, r$QEp, r$zval, r$pval, r$ci.lb, r$ci.ub)
    rel <- if (m %in% c(5, 6, 7)) 1e-2 else 1e-9
    for (w in 0:10) add("rma", c(m, w, k, yi, vi), vals[w + 1], if (w %in% c(5, 6)) 1e-9 else rel)
  }
}
emit("metaforpkg", "metafor", list(cases))
