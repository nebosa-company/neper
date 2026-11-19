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
  add("dfat", c(n, spar, x, y), fit$df, 1e-9)
}
# smooth.spline(x, y, df = df): "ssdf" (n, df, m, x[n], y[n], xo[m], index) index 0 .. m - 1 predict(fit, xo)$y, m the fitted spar, m + 1 lambda, m + 2 the df of the fit
for (rep in 1:25) {
  n <- sample(12:45, 1); x <- sort(runif(n, -2, 3)); x <- x + seq_len(n) * 1e-3; y <- sin(x) + rnorm(n, 0, 0.3); dfv <- sample(c(3, 4, 5, 6), 1)
  fit <- smooth.spline(x, y, df = dfv)
  xo <- c(runif(6, min(x), max(x)), min(x), max(x)); m <- length(xo); pr <- predict(fit, xo)$y
  for (j in seq_len(m)) cases[[length(cases) + 1]] <- case("ssdf", c(n, dfv, m, x, y, xo, j - 1), pr[j], rel = 5e-4, abs = 2e-4)
  cases[[length(cases) + 1]] <- case("ssdf", c(n, dfv, m, x, y, xo, m), fit$spar, rel = 1e-4, abs = 1e-4)
  cases[[length(cases) + 1]] <- case("ssdf", c(n, dfv, m, x, y, xo, m + 1), fit$lambda, rel = 2e-3, abs = 1e-9)
  cases[[length(cases) + 1]] <- case("ssdf", c(n, dfv, m, x, y, xo, m + 2), fit$df, rel = 1e-3, abs = 2e-3)
}
emit("smspline", "stats", list(cases))
