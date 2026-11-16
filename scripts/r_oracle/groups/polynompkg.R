# polynompkg: polynom's predict, deriv, integral, poly.calc, poly.orth and caTools colAUC (two classes).
#   "predict" (x, k, coefficients); "deriv" and "integral" (index, k, coefficients); "polycalc" (index, number of roots, roots); "polyorth" (degree, which, index, points count, points); "auc" (n, x, y)
suppressMessages(library(polynom)); suppressMessages(library(caTools))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-11)
set.seed(20262025)
for (rep in 1:30) {
  k <- sample(2:7, 1); cf <- round(rnorm(k), 3); p <- polynomial(cf)
  for (x in runif(2, -2, 2)) add("predict", c(x, k, cf), predict(p, x))
  d <- as.numeric(deriv(p)); for (i in seq_along(d)) add("deriv", c(i - 1, k, cf), d[i])
  ig <- as.numeric(integral(p)); for (i in seq_along(ig)) add("integral", c(i - 1, k, cf), ig[i])
  r <- round(runif(k - 1, -3, 3), 2); pc <- as.numeric(poly.calc(r)); for (i in seq_along(pc)) add("polycalc", c(i - 1, length(r), r), pc[i])
  np <- sample(5:12, 1); pts <- round(runif(np, -2, 2), 3); dg <- sample(1:min(4, np - 1), 1); po <- poly.orth(pts, dg)
  for (w in 0:dg) { co <- as.numeric(po[[w + 1]]); co <- c(co, rep(0, dg + 1 - length(co))); for (i in 0:dg) add("polyorth", c(dg, w, i, np, pts), co[i + 1]) }
  n <- sample(10:40, 1); yy <- sample(0:1, n, TRUE); if (length(unique(yy)) == 2) { xx <- round(rnorm(n), 2); add("auc", c(n, xx, yy), as.numeric(colAUC(xx, yy))) }
}
emit("polynompkg", "polynom", list(cases))
