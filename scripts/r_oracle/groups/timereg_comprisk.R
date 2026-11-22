# timereg comp.risk (competing-risks regression, nonparametric terms only): cumulative estimates and variances over the quantile time grid, the constant-effect estimate,
# and the resampled tests (supremum, constant effect, integrated squared) with their p-values and the 95% band, for each link (model). The censoring weights are the
# Kaplan-Meier ones, clusters are the subjects.
#   fn "s00".."s10": weighted sum (position, row-major) of cum, var.cum, gamma2, pval.testBeq0, pval.testBeqC, pval.testBeqC.is, obs.testBeq0, obs.testBeqC,
#   obs.testBeqC.is, conf.band, test.procBeqC
#   args: (n, px, trans, step, antsim, seed, tpow, ntm, firstp, cause, time[n], status[n], X[n*px])
suppressMessages({library(timereg); library(survival)})
cases <- list()
flat <- function(m) as.vector(t(as.matrix(m)))
models <- c("fg", "additive", "prop", "logistic", "rcif", "rcif2", "logistic2", "fg", "additive", "fg", "prop", "logistic")
trs <- c(additive = 1, prop = 2, logistic = 3, rcif = 4, rcif2 = 5, fg = 6, logistic2 = 7)
set.seed(20271301)
for (rep in seq_along(models)) {
  mo <- models[rep]
  n <- sample(70:110, 1); px <- sample(1:2, 1)
  x <- matrix(rnorm(n * 2), n)
  t1 <- rexp(n, 0.5 * exp(0.4 * x[, 1])); t2 <- rexp(n, 0.3); cc <- runif(n, 0, 6)
  tm <- pmin(t1, t2, cc) + seq_len(n) * 1e-9
  st <- ifelse(cc < pmin(t1, t2), 0, ifelse(t1 <= t2, 1, 2))
  d <- data.frame(time = tm, status = st, x1 = x[, 1], x2 = x[, 2])
  nsim <- sample(c(50, 100), 1); sd <- sample(1:100000, 1)
  fm <- if (px == 1) Event(time, status) ~ x1 else Event(time, status) ~ x1 + x2
  set.seed(sd)
  f <- tryCatch(suppressWarnings(comp.risk(fm, d, cause = 1, model = mo, n.sim = nsim)), error = function(e) NULL)
  set.seed(20271301 + rep)
  if (is.null(f) || any(!is.finite(f$cum)) || any(!is.finite(f$var.cum)) || any(f$conv$convp > 0)) next
  step <- if (mo %in% c("prop", "logistic", "logistic2")) 0.5 else 1
  tpow <- if (mo == "additive") 1 else 0
  X <- cbind(1, x[, seq_len(px), drop = FALSE])[, seq_len(px + 1), drop = FALSE]
  X <- cbind(1, x[, seq_len(px), drop = FALSE])
  a <- c(n, ncol(X), trs[[mo]], step, nsim, sd, tpow, 50, 0.05, 1, tm, st, as.vector(t(X)))
  sl <- list(f$cum, f$var.cum, f$gamma2, f$pval.testBeq0, f$pval.testBeqC, f$pval.testBeqC.is, f$obs.testBeq0, f$obs.testBeqC, f$obs.testBeqC.is, f$conf.band, f$test.procBeqC)
  for (j in 0:10) {
    v <- flat(sl[[j + 1]])
    cases[[length(cases) + 1]] <- case(sprintf("s%02d", j), a, sum(v * seq_along(v)), rel = 1e-9, abs = 1e-12)
  }
}
emit("timereg_comprisk", "timereg", list(cases))
