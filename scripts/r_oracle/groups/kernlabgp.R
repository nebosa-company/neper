# kernlab gausspr regression (scaled = FALSE): coefficients, fitted values, predictions and predictive standard deviations.
#   args: (m, nt, p, kind, par1, var, x[m*p], y[m], xt[nt*p]); kinds 0 rbfdot(par1), 4 laplacedot(par1)
#   fn "alpha" "fitted" "pred" "sdev" (position-weighted)
suppressMessages(library(kernlab))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-11) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
ws <- function(v) sum(as.vector(v) * seq_along(v))
set.seed(20261304)
for (rep in 1:16) {
  kind <- c(0, 4)[rep %% 2 + 1]
  m <- sample(15:40, 1); nt <- sample(5:12, 1); p <- sample(1:3, 1)
  x <- matrix(rnorm(m * p), m); xt <- matrix(rnorm(nt * p), nt); y <- sin(x[, 1]) + 0.2 * rnorm(m)
  s1 <- runif(1, 0.2, 1.2); v <- runif(1, 0.05, 1.5)
  kn <- if (kind == 0) rbfdot(s1) else laplacedot(s1)
  g <- gausspr(x, y, type = "regression", kernel = kn, var = v, scaled = FALSE, variance.model = TRUE)
  a <- c(m, nt, p, kind, s1, v, as.vector(t(x)), y, as.vector(t(xt)))
  add("alpha", a, ws(alpha(g))); add("fitted", a, ws(fitted(g)))
  add("pred", a, ws(predict(g, xt))); add("sdev", a, ws(predict(g, xt, type = "sdeviation")))
}
emit("kernlabgp", "kernlab", list(cases))
