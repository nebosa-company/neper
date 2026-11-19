# mgcv: summary.gam's parametric table and fit statistics for gam(y ~ s(x, bs = "cr", k = k), sp = sp). Args: (n, k, sp, what, x[n], y[n]):
# what 0 the intercept estimate, 1 its standard error, 2 t, 3 the p value, 4 the scale, 5 the adjusted r squared, 6 the deviance explained, 7 the total edf.
suppressMessages(library(mgcv))
cases <- list()
set.seed(20262308)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("sm", args, want, rel = 1e-7, abs = 1e-9)
for (rep in 1:12) {
  n <- sample(40:100, 1); k <- sample(6:12, 1); sp <- 10^runif(1, -2, 1.5)
  x <- sort(round(runif(n, 0, 10), 3)); y <- round(5 + sin(x) + 0.3 * x + rnorm(n, 0, 0.4), 4)
  f <- gam(y ~ s(x, bs = "cr", k = k), sp = sp); s <- summary(f)
  hdr <- function(w) c(n, k, sp, w, x, y)
  add(hdr(0), s$p.coeff[1]); add(hdr(1), s$se[1]); add(hdr(2), s$p.t[1] * 0 + s$p.coeff[1] / s$se[1]); add(hdr(3), s$p.pv[1])
  add(hdr(4), s$scale); add(hdr(5), s$r.sq); add(hdr(6), s$dev.expl); add(hdr(7), sum(f$edf))
}
emit("mgcv_summary", "mgcv", list(cases))
