# survival::coxph, Breslow and Efron ties, one stratum.
#   args: (n, p, efron, time[n], status[n], X[n*p] column-major, q)  q in 0..p-1 coefficient, p..2p-1 se, 2p loglik at 0, 2p+1 loglik at the fit
suppressMessages(library(survival))
cases <- list()
set.seed(20261116)
for (rep in 1:14) {
  n <- sample(25:70, 1); p <- sample(1:3, 1)
  X <- matrix(round(rnorm(n * p), 2), n, p)
  tm <- ceiling(rexp(n, exp(0.5 * X[, 1])) * 5) + ifelse(rep %% 2 == 0, 0, round(runif(n), 3))
  st <- rbinom(n, 1, 0.75); if (sum(st) < 5) st[1:6] <- 1
  for (ef in c(1, 0)) {
    f <- coxph(Surv(tm, st) ~ X, ties = if (ef) "efron" else "breslow", control = coxph.control(eps = 1e-12, iter.max = 50))
    a <- c(n, p, ef, tm, st, X)
    out <- c(coef(f), sqrt(diag(vcov(f))), f$loglik)
    for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("cox", c(a, q - 1), out[q], rel = 1e-6, abs = 1e-8)
  }
}
# strata, an offset and the robust variance: "coxs" args (n, p, efron, robust, time, status, strata (0-based), offset, X column-major, q) q in 0..p-1 coefficient, p..2p-1 se, 2p loglik at the fit
for (rep in 1:14) {
  n <- sample(30:60, 1); p <- sample(1:2, 1); X <- matrix(round(rnorm(n * p), 2), n, p)
  tm <- ceiling(rexp(n, exp(0.5 * X[, 1])) * 5) + ifelse(rep %% 2 == 0, 0, round(runif(n), 3)); st <- rbinom(n, 1, 0.75); if (sum(st) < 6) st[1:8] <- 1
  sg <- sample(0:2, n, TRUE); off <- round(rnorm(n, 0, 0.3), 2)
  for (cfg in list(c(1, 0), c(0, 0), c(0, 1))) {
    ef <- cfg[1]; rb <- cfg[2]
    f <- coxph(Surv(tm, st) ~ X + strata(sg) + offset(off), ties = if (ef) "efron" else "breslow", robust = rb == 1, control = coxph.control(eps = 1e-12, iter.max = 50))
    a <- c(n, p, ef, rb, tm, st, sg, off, X)
    se <- if (rb == 1) sqrt(diag(f$var)) else sqrt(diag(vcov(f)))
    out <- c(coef(f), se, f$loglik[2])
    for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("coxs", c(a, q - 1), out[q], rel = 1e-6, abs = 1e-8)
  }
}
emit("coxph", "survival", list(cases))
