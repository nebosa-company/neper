# timereg cox.aalen (Cox-Aalen model): cumulative additive effects, proportional effects, martingale and robust variances, the score-process (proportionality) test
# and, with basesim = 1, the resampled tests and 95% band of the cumulative effects. Starting values are coxph's, as cox.aalen takes them by default.
#   fn "s00".."s15": weighted sum (position, row-major) of cum, var.cum, robvar.cum, gamma, var.gamma, robvar.gamma, score, test.procProp, pval.Prop, conf.band,
#   obs.testBeq0, obs.testBeqC, pval.testBeq0, pval.testBeqC, D2linv, loglike (s09-s13 only when basesim = 1)
#   args: (n, px, pg, antsim, seed, bs, maxt, y[n], event[n], X[n*px], Z[n*pg], beta0[pg])
suppressMessages({library(timereg); library(survival)})
cases <- list()
flat <- function(m) as.vector(t(as.matrix(m)))
set.seed(20271101)
for (rep in 1:14) {
  n <- sample(40:70, 1); px <- sample(1:3, 1); pg <- sample(1:2, 1)
  zz <- matrix(rnorm(n * pg), n); xx <- matrix(rnorm(n * 2), n)
  tt <- rexp(n, exp(0.4 * zz[, 1])) + runif(n) * 1e-4; cc <- runif(n, 0, 2.5)
  y <- pmin(tt, cc) + seq_len(n) * 1e-9; ev <- as.numeric(tt <= cc)
  mt <- sort(y)[n - 10]
  d <- data.frame(y, ev); for (k in seq_len(pg)) d[[paste0("z", k)]] <- zz[, k]; d$x1 <- xx[, 1]; d$x2 <- xx[, 2]
  nsim <- sample(c(50, 100), 1); sd <- sample(1:100000, 1); bs <- as.numeric(px > 1 && rep %% 2 == 0)
  zt <- paste0("prop(z", seq_len(pg), ")", collapse = " + ")
  xt <- if (px == 1) "" else paste0("+ ", paste0("x", seq_len(px - 1), collapse = " + "))
  fm <- as.formula(paste("Surv(y, ev) ~", zt, xt))
  b0 <- as.numeric(coxph(as.formula(paste("Surv(y, ev) ~", paste0("z", seq_len(pg), collapse = " + "))), d)$coef)
  set.seed(sd)
  f <- tryCatch(cox.aalen(fm, d, beta = b0, n.sim = nsim, max.time = mt, basesim = bs, robust = 1, silent = 1), error = function(e) NULL)
  if (is.null(f)) { set.seed(20271101 + rep); next }
  X <- cbind(1, xx[, seq_len(px - 1), drop = FALSE])[, seq_len(px), drop = FALSE]
  a <- c(n, px, pg, nsim, sd, bs, mt, y, ev, as.vector(t(X)), as.vector(t(zz)), b0)
  sl <- list(f$cum, f$var.cum, f$robvar.cum, f$gamma, f$var.gamma, f$robvar.gamma, f$score, f$test.procProp, f$pval.Prop, f$conf.band,
             f$obs.testBeq0, f$obs.testBeqC, f$pval.testBeq0, f$pval.testBeqC, f$D2linv, f$loglike)
  for (j in 0:15) {
    if (is.null(sl[[j + 1]])) next
    v <- flat(sl[[j + 1]])
    cases[[length(cases) + 1]] <- case(sprintf("s%02d", j), a, sum(v * seq_along(v)), rel = 1e-9, abs = 1e-12)
  }
  set.seed(20271101 + rep)
}
emit("timereg_coxaalen", "timereg", list(cases))
