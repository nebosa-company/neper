# timereg aalen: Aalen additive hazards with an intercept, cumulative coefficients at the event times (distinct times).
#   args: (n, p, time[n], event[n], x[n*p] row-major)
#   fn "last" (the final cumulative row, weighted by position), "sum" (every cumulative entry weighted by position, row-major), "rows" (number of event times)
suppressMessages({library(timereg); library(survival)})
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-7, abs = 1e-9)
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
emit("timereg", "timereg", list(cases))
