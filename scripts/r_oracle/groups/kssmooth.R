# stats smooth.spline(x, y, spar = s) with predict(), the smoother kroc in ks applies to its ROC curve.
#   args: (n, spar, xp, x[n], y[n]); want predict(fit, xp)$y
set.seed(20262014)
cases <- list()
add <- function(args, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case("ss", args, want, rel = rel, abs = 1e-12)
for (rep in 1:14) {
  n <- sample(c(12, 25, 40, 80, 150, 300), 1)
  x <- sort(runif(n))
  if (rep %% 3 == 0) x <- round(x, 2)
  if (rep %% 2 == 0) x <- sample(x)
  y <- sin(6 * x) + rnorm(n, 0, 0.3)
  for (spar in c(0.2, 0.5, 0.8)) {
    f <- smooth.spline(x, y, spar = spar)
    for (xp in c(min(x) - 0.1, min(x), 0.5 * (min(x) + max(x)), runif(2, min(x), max(x)), max(x), max(x) + 0.2))
      add(c(n, spar, xp, x, y), predict(f, xp)$y)
  }
}
emit("kssmooth", "stats", list(cases))
