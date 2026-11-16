# polspline: dlogspline, plogspline, qlogspline of fitted logspline models.
#   "ls" args (nk, c0, c1, kc[nk], knots[nk], lower, lo, upper, hi, fn, x): fn 0 density 1 log density 2 distribution 3 quantile
suppressMessages(library(polspline))
cases <- list()
set.seed(20261116)
for (rep in 1:24) {
  n <- sample(100:400, 1)
  x <- switch(rep %% 4 + 1, rnorm(n), rexp(n), c(rnorm(n / 2), rnorm(n / 2, 4)), rgamma(n, 3))
  f <- switch(rep %% 3 + 1, logspline(x), logspline(x, lbound = min(x) - 0.5), logspline(x, lbound = min(x) - 0.5, ubound = max(x) + 0.5))
  b <- f$bound
  pre <- c(length(f$knots), f$coef.pol, f$coef.kts, f$knots, b[1], b[2], b[3], b[4])
  add <- function(fn, q, v) cases[[length(cases) + 1]] <<- case("ls", c(pre, fn, q), as.numeric(v), rel = 1e-6, abs = 1e-8)
  qs <- sort(runif(12, min(x) - 1, max(x) + 1))
  for (q in qs) { add(0, q, dlogspline(q, f)); add(1, q, dlogspline(q, f, log = TRUE)); add(2, q, plogspline(q, f)) }
  for (p in c(0.01, 0.1, 0.25, 0.5, 0.75, 0.9, 0.99)) add(3, p, qlogspline(p, f))
}
emit("polspline", "polspline", list(cases))
