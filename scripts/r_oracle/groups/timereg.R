# timereg aalen: Aalen additive hazards with an intercept, cumulative coefficients at the event times (distinct times).
#   args: (n, p, time[n], event[n], x[n*p] row-major)
#   fn "last" (the final cumulative row, weighted by position), "sum" (every cumulative entry weighted by position, row-major), "rows" (number of event times)
suppressMessages({library(timereg); library(survival)})
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20270103)
for (rep in 1:24) {
  n <- sample(30:120, 1); p <- sample(1:3, 1); x <- matrix(rnorm(n * p), n)
  tt <- rexp(n, exp(0.3 * x[, 1])) + (runif(n) * 1e-4); cc <- runif(n, 0, 2.5); y <- pmin(tt, cc) + seq_len(n) * 1e-9; ev <- as.numeric(tt <= cc)
  d <- data.frame(y, ev, x); names(d)[-(1:2)] <- paste0("x", seq_len(p))
  f <- tryCatch(aalen(as.formula(paste("Surv(y, ev) ~", paste0("x", seq_len(p), collapse = " + "))), d, n.sim = 0, robust = 0), error = function(e) NULL)
  if (is.null(f)) next
  cm <- f$cum[-1, -1, drop = FALSE]; a <- c(n, p, y, ev, as.vector(t(x)))
  add("rows", a, nrow(cm)); add("last", a, sum(cm[nrow(cm), ] * seq_len(ncol(cm)))); add("sum", a, sum(as.vector(t(cm)) * seq_along(cm)))
}
# fn "slice<j>" (j = 0..8): aalen(n.sim = antsim, robust = 1, max.time) after set.seed(seed); weighted sum (position) of slice j of
#   obs.testBeq0, obs.testBeqC, obs.testBeqC.is, pval.testBeq0, pval.testBeqC, pval.testBeqC.is, conf.band, last robvar.cum row, last var.cum row.
#   args: (n, p, antsim, seed, maxt, time[n], event[n], x[n*p])
set.seed(20270411)
for (rep in 1:10) {
  n <- sample(40:70, 1); p <- sample(1:3, 1); x <- matrix(rnorm(n * p), n); nsim <- sample(c(50, 100), 1); sd <- sample(1:100000, 1)
  tt <- rexp(n, exp(0.3 * x[, 1])) + (runif(n) * 1e-4); cc <- runif(n, 0, 2.5); y <- pmin(tt, cc) + seq_len(n) * 1e-9; ev <- as.numeric(tt <= cc)
  mt <- sort(y)[n - 10]
  d <- data.frame(y, ev, x); names(d)[-(1:2)] <- paste0("x", seq_len(p))
  set.seed(sd)
  f <- tryCatch(aalen(as.formula(paste("Surv(y, ev) ~", paste0("x", seq_len(p), collapse = " + "))), d, n.sim = nsim, robust = 1, max.time = mt, silent = 1), error = function(e) NULL)
  if (is.null(f)) next
  nr <- nrow(f$cum); a <- c(n, p, nsim, sd, mt, y, ev, as.vector(t(x)))
  sl <- list(f$obs.testBeq0, f$obs.testBeqC, f$obs.testBeqC.is, f$pval.testBeq0, f$pval.testBeqC, f$pval.testBeqC.is, f$conf.band, f$robvar.cum[nr, -1], f$var.cum[nr, -1])
  for (j in 0:8) { v <- as.numeric(sl[[j + 1]]); cases[[length(cases) + 1]] <- case(paste0("slice", j), a, sum(v * seq_along(v)), rel = 1e-9, abs = 1e-12) }
  set.seed(20270411 + rep)
}
emit("timereg", "timereg", list(cases))
