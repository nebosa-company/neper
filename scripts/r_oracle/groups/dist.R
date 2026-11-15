# R's d, p, q for norm, unif, exp, weibull, logis, cauchy and lnorm, with lower.tail and log.p.
#   args: (family, kind 0 d 1 p 2 q, x, p1, p2, lower, log)   family 0 norm(mean, sd) 1 unif(min, max) 2 exp(scale) 3 weibull(shape, scale)
#   4 logis(location, scale) 5 cauchy(location, scale) 6 lnorm(meanlog, sdlog)
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("dist", args, want, rel = 1e-13, abs = 1e-300)
fam <- list(
  list(function(x, a, b, lt, lg) dnorm(x, a, b, lg), function(x, a, b, lt, lg) pnorm(x, a, b, lt, lg), function(x, a, b, lt, lg) qnorm(x, a, b, lt, lg)),
  list(function(x, a, b, lt, lg) dunif(x, a, b, lg), function(x, a, b, lt, lg) punif(x, a, b, lt, lg), function(x, a, b, lt, lg) qunif(x, a, b, lt, lg)),
  list(function(x, a, b, lt, lg) dexp(x, 1 / a, lg), function(x, a, b, lt, lg) pexp(x, 1 / a, lt, lg), function(x, a, b, lt, lg) qexp(x, 1 / a, lt, lg)),
  list(function(x, a, b, lt, lg) dweibull(x, a, b, lg), function(x, a, b, lt, lg) pweibull(x, a, b, lt, lg), function(x, a, b, lt, lg) qweibull(x, a, b, lt, lg)),
  list(function(x, a, b, lt, lg) dlogis(x, a, b, lg), function(x, a, b, lt, lg) plogis(x, a, b, lt, lg), function(x, a, b, lt, lg) qlogis(x, a, b, lt, lg)),
  list(function(x, a, b, lt, lg) dcauchy(x, a, b, lg), function(x, a, b, lt, lg) pcauchy(x, a, b, lt, lg), function(x, a, b, lt, lg) qcauchy(x, a, b, lt, lg)),
  list(function(x, a, b, lt, lg) dlnorm(x, a, b, lg), function(x, a, b, lt, lg) plnorm(x, a, b, lt, lg), function(x, a, b, lt, lg) qlnorm(x, a, b, lt, lg)))
params <- list(list(c(0, 1), c(1.5, 2), c(-2, 0.3)), list(c(0, 1), c(-1, 3), c(2, 2.5)), list(c(1, 0), c(0.5, 0), c(4, 0)),
               list(c(1, 1), c(2, 3), c(0.5, 2)), list(c(0, 1), c(2, 3), c(-1, 0.5)), list(c(0, 1), c(1, 2), c(-3, 0.1)),
               list(c(0, 1), c(1, 0.5), c(-2, 2)))
xs <- c(-Inf, -50, -40, -38.5, -20, -10, -8.5, -6, -5.7, -5.6, -3, -1.5, -0.7, -0.5, -1e-5, 0, 1e-5, 0.1, 0.5, 0.7, 1, 1.5, 2, 3.3, 5, 5.6, 5.7, 6, 8, 8.5, 10, 20, 38, 39, 50, 100, Inf)
ps <- c(0, 1e-320, 1e-317, 1e-310, 1e-300, 1e-100, 1e-20, 1e-8, 0.001, 0.1, 0.25, 0.4, 0.5, 0.6, 0.75, 0.9, 0.99, 1 - 1e-8, 1)
lps <- c(-Inf, -1e20, -1e18, -1e12, -1e7, -1e5, -1000, -100, -30, -10, -2, -0.7, -0.1, -1e-5, -1e-20, 0)
for (f in seq_along(fam)) for (pp in params[[f]]) for (lt in c(TRUE, FALSE)) for (lg in c(FALSE, TRUE)) {
  for (x in xs) {
    r <- suppressWarnings(fam[[f]][[1]](x, pp[1], pp[2], lt, lg)); if (lt && !lg || TRUE) {}
    if (lt) { if (!lg) add(c(f - 1, 0, x, pp, 1, 0), r) }
    add(c(f - 1, 1, x, pp, lt, lg), suppressWarnings(fam[[f]][[2]](x, pp[1], pp[2], lt, lg)))
  }
  for (p in if (lg) lps else ps) {
    r <- suppressWarnings(fam[[f]][[3]](p, pp[1], pp[2], lt, lg))
    if (is.finite(r) || is.infinite(r)) add(c(f - 1, 2, p, pp, lt, lg), r)
  }
}
for (f in seq_along(fam)) for (pp in params[[f]]) for (x in xs) add(c(f - 1, 0, x, pp, 1, 1), suppressWarnings(fam[[f]][[1]](x, pp[1], pp[2], TRUE, TRUE)))
emit("dist", character(), list(cases))
