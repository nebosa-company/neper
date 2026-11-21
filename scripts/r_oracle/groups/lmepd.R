# nlme::lme with the pdDiag, pdIdent and pdCompSymm random-effects classes (the default pdLogChol is in nlmelist.R).
# Same case layout as the lme family of nlmelist.R, checked by the same fixture (oracle_nlmelist): c(1, q_out, reml, n, p, ck, nv, ng, gs[ng], t[n], y[n],
# X[n*p] column-major, 100 pd + qz, Z[n*qz], then per variance term c(kind, nstr, v[n])); pd: 1 pdDiag, 2 pdIdent, 3 pdCompSymm.
# Output vector: coef (p), sigma, logLik, AIC, BIC, random-effect sd (qz), random-effect correlations (lower triangle by columns), natural correlation
# parameters, natural variance parameters, se (p), ranef (group-major, first three groups). No intervals (nlme's var-cov intervals are not compared for these classes).
# Measured on R 4.6.1 / nlme 3.1.169 (Orthodont, ML, only the corAR1 start value changed 0.05 / 0.2 / 0.4): lme estimates spread by 6e-6 relative with pdSymm + corAR1 and
# 1.1e-6 with pdDiag + corAR1 + varPower (logLik 6e-11), so R's own stopping point is the limit of any reference taken from one lme run.
# R's lme (nlminb, msTol 1e-12) stops about 1e-6 from the optimum of the likelihood, so the estimates carry rel 2e-4 / abs 1e-5 and logLik, AIC, BIC 1e-9
# (the likelihood is flat at its optimum, second order in that distance); the BLUPs move ~1e-5 with it: rel 5e-4 / abs 2e-4.
suppressMessages(library(nlme))
cases <- list()
set.seed(20261121)
ctl <- lmeControl(opt = "nlminb", msTol = 1e-12, tolerance = 1e-10, msMaxIter = 500, msMaxEval = 1000, maxIter = 200, niterEM = 25, returnObject = FALSE, x.tol = 1e-11, xf.tol = 1e-11)
mkdata <- function(ng, m, p, qz) {
  n <- ng * m
  g <- rep(seq_len(ng), each = m)
  pos <- rep(seq_len(m), ng)
  X <- cbind(1, matrix(round(rnorm(n * (p - 1)), 3), n, p - 1))
  v <- round(runif(n, 0.5, 3), 3)
  Z <- X[, seq_len(qz), drop = FALSE]
  b <- matrix(rnorm(ng * qz, 0, c(3, 2.5, 2)[seq_len(qz)]), ng, qz, byrow = TRUE)
  e <- unlist(lapply(seq_len(ng), function(i) as.numeric(arima.sim(list(ar = 0.4), m))))
  y <- round(drop(X %*% (1:p)) + rowSums(Z * b[g, , drop = FALSE]) + e * exp(0.15 * v), 3)
  d <- data.frame(y = y, t = pos, g = factor(g), v = v)
  for (k in 2:p) d[[paste0("x", k)]] <- X[, k]
  list(d = d, X = X, Z = Z, n = n, ng = ng, m = m, p = p, qz = qz)
}
pdf <- function(pd, qz) {
  fm <- if (qz == 1) ~ 1 else if (qz == 2) ~ x2 else ~ x2 + x3
  switch(pd, pdDiag(fm), pdIdent(fm), pdCompSymm(fm))
}
# cfg: pd, random effects, correlation (0 none, 1 AR1), variance (0 none, 2 varPower), reml
cfgs <- list(c(1, 2, 0, 0, 1), c(1, 3, 0, 0, 0), c(1, 3, 0, 0, 1), c(2, 2, 0, 0, 1), c(2, 3, 0, 0, 0), c(2, 3, 0, 0, 1), c(2, 1, 0, 0, 1),
             c(3, 2, 0, 0, 1), c(3, 3, 0, 0, 1), c(3, 3, 0, 0, 0), c(1, 2, 1, 2, 1), c(2, 3, 1, 0, 0), c(3, 3, 0, 2, 1))
for (cf in cfgs) {
  pd <- cf[1]; qz <- cf[2]; ck <- cf[3]; vk <- cf[4]; reml <- cf[5]
  D <- mkdata(9, 5, 3, qz)
  fx <- y ~ x2 + x3
  cr <- if (ck == 1) corAR1(form = ~ t | g) else NULL
  wt <- if (vk == 2) varPower(form = ~ v) else NULL
  f <- tryCatch(lme(fx, data = D$d, random = list(g = pdf(pd, qz)), correlation = cr, weights = wt, method = if (reml) "REML" else "ML", control = ctl),
                error = function(e) { message("skip pd=", pd, " q=", qz, ": ", conditionMessage(e)); NULL })
  if (is.null(f)) next
  vc <- getVarCov(f)
  cn <- if (ck == 0) numeric(0) else as.numeric(coef(f$modelStruct$corStruct, unconstrained = FALSE))
  vn <- if (vk == 0) numeric(0) else as.numeric(unlist(coef(f$modelStruct$varStruct, unconstrained = FALSE)))
  ov <- c(fixef(f), f$sigma, as.numeric(logLik(f)), AIC(f), BIC(f), sqrt(diag(vc)), if (qz > 1) cov2cor(vc)[lower.tri(vc)], cn, vn,
          sqrt(diag(vcov(f))), as.numeric(t(as.matrix(ranef(f))))[seq_len(3 * qz)])
  vstr <- if (vk == 2) c(2, 0, D$d$v) else numeric(0)
  args0 <- c(reml, D$n, D$p, ck, as.integer(vk == 2), D$ng, rep(D$m, D$ng), D$d$t, D$d$y, D$X, 100 * pd + qz, D$Z, vstr)
  for (q in seq_along(ov)) {
    tight <- q >= D$p + 2 && q <= D$p + 4
    blup <- q > length(ov) - 3 * qz
    cases[[length(cases) + 1]] <- case("nl", c(1, q - 1, args0), ov[q], rel = if (tight) 1e-9 else if (blup) 5e-4 else 2e-4, abs = if (tight) 1e-9 else if (blup) 2e-4 else 1e-5)
  }
}
emit("lmepd", "nlme", list(cases))
