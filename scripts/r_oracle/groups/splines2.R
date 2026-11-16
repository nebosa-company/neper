# splines2: bSpline (and derivatives), mSpline, iSpline on explicit knots; each matrix is summarised as the sum and the
# position-weighted sum (row-major index) of its entries.
#   args: (n, nk, degree, intercept, lo, hi, kind, x[n], knots[nk])  kind 0 bSpline 1 mSpline 2 iSpline 3 bSpline derivs 1 4 bSpline derivs 2
#   fn "sum" "w"
suppressMessages(library(splines2))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-11)
set.seed(20261116)
for (rep in 1:40) {
  lo <- sample(c(0, -1, 2), 1); hi <- lo + sample(c(1, 3), 1); n <- sample(5:20, 1)
  nk <- sample(0:3, 1); degree <- sample(1:4, 1); icp <- rbinom(1, 1, 0.5)
  x <- sort(c(lo, hi, round(runif(n - 2, lo, hi), 4)))
  kn <- if (nk > 0) sort(round(runif(nk, lo + 0.05 * (hi - lo), hi - 0.05 * (hi - lo)), 3)) else numeric(0)
  if (anyDuplicated(kn)) next
  for (kind in 0:4) {
    a <- c(n, nk, degree, icp, lo, hi, kind, x, kn)
    m <- unclass(switch(kind + 1,
      bSpline(x, knots = kn, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi)),
      mSpline(x, knots = kn, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi)),
      iSpline(x, knots = kn, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi)),
      bSpline(x, knots = kn, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi), derivs = 1),
      bSpline(x, knots = kn, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi), derivs = 2)))
    v <- as.vector(t(m[, seq_len(ncol(m))]))
    add("sum", a, sum(v)); add("w", a, sum(seq_along(v) * v))
  }
}
emit("splines2", "splines2", list(cases))
