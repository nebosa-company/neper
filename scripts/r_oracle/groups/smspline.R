# smooth.spline(x, y, spar) and predict: "ss" (n, spar, m, x[n], y[n], xo[m], index) answers predict(fit, xo)$y[index]; "lam" (n, spar, x[n], y[n]) the lambda of the fit
suppressMessages(library(stats))
cases <- list()
add <- function(fn, args, want, tol = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = tol, abs = 1e-11)
set.seed(20261118)
for (rep in 1:30) {
  n <- sample(8:45, 1); x <- sort(runif(n, -2, 3)); x <- x + seq_len(n) * 1e-3; y <- sin(x) + rnorm(n, 0, 0.3); spar <- sample(c(0.25, 0.4, 0.6, 0.9), 1)
  fit <- smooth.spline(x, y, spar = spar)
  xo <- c(runif(6, min(x), max(x)), min(x), max(x), min(x) - 0.5, max(x) + 0.7); m <- length(xo); pr <- predict(fit, xo)$y
  for (j in seq_len(m)) add("ss", c(n, spar, m, x, y, xo, j - 1), pr[j], 1e-8)
  add("lam", c(n, spar, x, y), fit$lambda)
}
emit("smspline", "stats", list(cases))
