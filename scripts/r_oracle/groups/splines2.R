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
# naturalSpline (kind 5): the cubic natural basis, as splines::ns builds it
for (rep in 1:20) {
  lo <- sample(c(0, -1, 2), 1); hi <- lo + sample(c(1, 3), 1); n <- sample(5:20, 1); nk <- sample(2:4, 1); icp <- rbinom(1, 1, 0.5)
  x <- sort(c(lo, hi, round(runif(n - 2, lo, hi), 4)))
  kn <- sort(round(runif(nk, lo + 0.05 * (hi - lo), hi - 0.05 * (hi - lo)), 3)); if (anyDuplicated(kn)) next
  m <- unclass(naturalSpline(x, knots = kn, intercept = icp == 1, Boundary.knots = c(lo, hi))); v <- as.vector(t(m)); a <- c(n, nk, 3, icp, lo, hi, 5, x, kn)
  add("sum", a, sum(v)); add("w", a, sum(seq_along(v) * v))
}
# cSpline (kinds 6 unscaled, 7 scaled)
for (rep in 1:30) {
  lo <- sample(c(0, -1, 2), 1); hi <- lo + sample(c(1, 3), 1); n <- sample(5:20, 1); nk <- sample(0:3, 1); degree <- sample(1:4, 1); icp <- rbinom(1, 1, 0.5)
  x <- sort(c(lo, hi, round(runif(n - 2, lo, hi), 4))); kn <- if (nk > 0) sort(round(runif(nk, lo + 0.05 * (hi - lo), hi - 0.05 * (hi - lo)), 3)) else numeric(0); if (anyDuplicated(kn)) next
  for (kind in 6:7) {
    m <- unclass(cSpline(x, knots = kn, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi), scale = kind == 7)); v <- as.vector(t(m)); a <- c(n, nk, degree, icp, lo, hi, kind, x, kn)
    add("sum", a, sum(v)); add("w", a, sum(seq_along(v) * v))
  }
}
# cSpline (kind 6 unscaled, kind 7 scaled)
for (rep in 1:30) {
  lo <- sample(c(0, -1, 2), 1); hi <- lo + sample(c(1, 3), 1); n <- sample(5:20, 1); nk <- sample(0:3, 1); degree <- sample(1:4, 1); icp <- rbinom(1, 1, 0.5)
  x <- sort(c(lo, hi, round(runif(n - 2, lo, hi), 4))); kn <- if (nk > 0) sort(round(runif(nk, lo + 0.05 * (hi - lo), hi - 0.05 * (hi - lo)), 3)) else numeric(0); if (anyDuplicated(kn)) next
  for (kind in 6:7) { m <- unclass(cSpline(x, knots = kn, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi), scale = kind == 7)); v <- as.vector(t(m)); a <- c(n, nk, degree, icp, lo, hi, kind, x, kn)
    add("sum", a, sum(v)); add("w", a, sum(seq_along(v) * v)) }
}
# derivatives of the M- and I-splines: kinds 8 mSpline derivs 1, 9 mSpline derivs 2, 10 iSpline derivs 1, 11 iSpline derivs 2
for (rep in 1:30) {
  lo <- sample(c(0, -1, 2), 1); hi <- lo + sample(c(1, 3), 1); n <- sample(5:20, 1); nk <- sample(0:3, 1); degree <- sample(2:4, 1); icp <- rbinom(1, 1, 0.5)
  x <- sort(c(lo, hi, round(runif(n - 2, lo, hi), 4))); kn <- if (nk > 0) sort(round(runif(nk, lo + 0.05 * (hi - lo), hi - 0.05 * (hi - lo)), 3)) else numeric(0); if (anyDuplicated(kn)) next
  for (kind in 8:11) {
    m <- unclass(if (kind <= 9) mSpline(x, knots = kn, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi), derivs = kind - 7) else iSpline(x, knots = kn, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi), derivs = kind - 9))
    v <- as.vector(t(m)); a <- c(n, nk, degree, icp, lo, hi, kind, x, kn); add("sum", a, sum(v)); add("w", a, sum(seq_along(v) * v))
  }
}
# derivatives of M- and I-splines: kind 8 M derivs 1, 9 M derivs 2, 10 I derivs 1, 11 I derivs 2
for (rep in 1:30) {
  lo <- sample(c(0, -1, 2), 1); hi <- lo + sample(c(1, 3), 1); n <- sample(5:20, 1); nk <- sample(0:3, 1); degree <- sample(2:4, 1); icp <- rbinom(1, 1, 0.5)
  x <- sort(c(lo, hi, round(runif(n - 2, lo, hi), 4))); kn <- if (nk > 0) sort(round(runif(nk, lo + 0.05 * (hi - lo), hi - 0.05 * (hi - lo)), 3)) else numeric(0); if (anyDuplicated(kn)) next
  for (kind in 8:11) { m <- unclass(switch(kind - 7, mSpline(x, knots = kn, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi), derivs = 1), mSpline(x, knots = kn, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi), derivs = 2),
      iSpline(x, knots = kn, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi), derivs = 1), iSpline(x, knots = kn, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi), derivs = 2)))
    v <- as.vector(t(m)); a <- c(n, nk, degree, icp, lo, hi, kind, x, kn); add("sum", a, sum(v)); add("w", a, sum(seq_along(v) * v)) }
}
# periodic bSpline (kind 12) and mSpline (kind 13)
for (rep in 1:30) {
  lo <- sample(c(0, -1, 2), 1); hi <- lo + sample(c(1, 3), 1); n <- sample(5:20, 1); nk <- sample(1:4, 1); degree <- sample(1:min(4, nk + 1), 1); icp <- rbinom(1, 1, 0.5)
  x <- sort(c(lo, hi, round(runif(n - 2, lo, hi), 4))); kn <- sort(round(runif(nk, lo + 0.05 * (hi - lo), hi - 0.05 * (hi - lo)), 3)); if (anyDuplicated(kn)) next
  for (kind in 12:13) { m <- tryCatch(unclass(if (kind == 12) bSpline(x, knots = kn, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi), periodic = TRUE) else mSpline(x, knots = kn, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi), periodic = TRUE)), error = function(e) NULL); if (is.null(m)) next
    v <- as.vector(t(m)); a <- c(n, nk, degree, icp, lo, hi, kind, x, kn); add("sum", a, sum(v)); add("w", a, sum(seq_along(v) * v)) }
}
# ibs, the integral of the B-splines (kind 14)
for (rep in 1:30) {
  lo <- sample(c(0, -1, 2), 1); hi <- lo + sample(c(1, 3), 1); n <- sample(5:20, 1); nk <- sample(0:3, 1); degree <- sample(1:4, 1); icp <- rbinom(1, 1, 0.5)
  x <- sort(c(lo, hi, round(runif(n - 2, lo, hi), 4))); kn <- if (nk > 0) sort(round(runif(nk, lo + 0.05 * (hi - lo), hi - 0.05 * (hi - lo)), 3)) else numeric(0); if (anyDuplicated(kn)) next
  m <- unclass(ibs(x, knots = kn, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi))); v <- as.vector(t(m)); a <- c(n, nk, degree, icp, lo, hi, 14, x, kn); add("sum", a, sum(v)); add("w", a, sum(seq_along(v) * v))
}
# bernsteinPoly (kinds 15 values, 16 derivs 1, 17 derivs 2)
for (rep in 1:30) {
  lo <- sample(c(0, -1, 2), 1); hi <- lo + sample(c(1, 3), 1); n <- sample(5:20, 1); degree <- sample(2:6, 1); icp <- rbinom(1, 1, 0.5)
  x <- sort(c(lo, hi, round(runif(n - 2, lo, hi), 4)))
  for (kind in 15:17) {
    m <- unclass(bernsteinPoly(x, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi), derivs = kind - 15)); v <- as.vector(t(m)); a <- c(n, 0, degree, icp, lo, hi, kind, x); add("sum", a, sum(v)); add("w", a, sum(seq_along(v) * v))
  }
}
# nsk (kind 18), the cardinal natural splines at the knots
for (rep in 1:30) {
  lo <- sample(c(0, -1, 2), 1); hi <- lo + sample(c(1, 3), 1); n <- sample(5:20, 1); nk <- sample(2:4, 1); icp <- rbinom(1, 1, 0.5)
  x <- sort(c(lo, hi, round(runif(n - 2, lo, hi), 4))); kn <- sort(round(runif(nk, lo + 0.05 * (hi - lo), hi - 0.05 * (hi - lo)), 3)); if (anyDuplicated(kn)) next
  m <- unclass(nsk(x, knots = kn, intercept = icp == 1, Boundary.knots = c(lo, hi))); v <- as.vector(t(m)); a <- c(n, nk, 3, icp, lo, hi, 18, x, kn); add("sum", a, sum(v)); add("w", a, sum(seq_along(v) * v))
}
# df instead of knots (kind + 100, the df in the knot-count slot): bSpline (0), mSpline (1), iSpline (2)
for (rep in 1:40) {
  lo <- sample(c(0, -1, 2), 1); hi <- lo + sample(c(1, 3), 1); n <- sample(8:30, 1); degree <- sample(1:4, 1); icp <- rbinom(1, 1, 0.5)
  x <- sort(c(lo, hi, round(runif(n - 2, lo, hi), 4))); df <- degree + sample(1:4, 1) + icp
  for (kind in 0:2) {
    m <- tryCatch(unclass(switch(kind + 1, bSpline(x, df = df, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi)), mSpline(x, df = df, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi)), iSpline(x, df = df, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi)))), error = function(e) NULL); if (is.null(m)) next
    v <- as.vector(t(m)); a <- c(n, df, degree, icp, lo, hi, kind + 100, x); add("sum", a, sum(v)); add("w", a, sum(seq_along(v) * v))
  }
}
# x beyond the boundary knots: bSpline (0), mSpline (1), iSpline (2), derivs 1 of bSpline (3)
for (rep in 1:40) {
  lo <- sample(c(0, -1, 2), 1); hi <- lo + sample(c(1, 3), 1); n <- sample(8:25, 1); degree <- sample(1:4, 1); icp <- rbinom(1, 1, 0.5); nk <- sample(0:3, 1)
  x <- sort(round(runif(n, lo - 1, hi + 1), 4)); kn <- if (nk > 0) sort(round(runif(nk, lo + 0.05 * (hi - lo), hi - 0.05 * (hi - lo)), 3)) else numeric(0); if (anyDuplicated(kn)) next
  for (kind in c(0, 1, 2, 3)) {
    m <- tryCatch(suppressWarnings(unclass(switch(kind + 1, bSpline(x, knots = kn, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi)), mSpline(x, knots = kn, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi)), iSpline(x, knots = kn, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi)), bSpline(x, knots = kn, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi), derivs = 1)))), error = function(e) NULL); if (is.null(m)) next
    v <- as.vector(t(m)); a <- c(n, nk, degree, icp, lo, hi, kind, x, kn); add("sum", a, sum(v)); add("w", a, sum(seq_along(v) * v))
  }
}
# periodic = TRUE for iSpline (kind 2) and cSpline (kinds 6, 7), which the package computes as the ordinary bases, and mSpline(integral = TRUE) (kind 2)
for (rep in 1:30) {
  lo <- sample(c(0, -1, 2), 1); hi <- lo + sample(c(1, 3), 1); n <- sample(5:20, 1); nk <- sample(1:3, 1); degree <- sample(1:4, 1); icp <- rbinom(1, 1, 0.5)
  x <- sort(c(lo, hi, round(runif(n - 2, lo, hi), 4))); kn <- sort(round(runif(nk, lo + 0.05 * (hi - lo), hi - 0.05 * (hi - lo)), 3)); if (anyDuplicated(kn)) next
  for (kind in c(2, 6, 7, 22)) {
    m <- tryCatch(suppressWarnings(unclass(switch(kind %% 20 - 1, iSpline(x, knots = kn, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi), periodic = TRUE), NULL, NULL, NULL, cSpline(x, knots = kn, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi), periodic = TRUE), cSpline(x, knots = kn, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi), scale = FALSE, periodic = TRUE)))), error = function(e) NULL)
    if (kind == 22) m <- tryCatch(suppressWarnings(unclass(mSpline(x, knots = kn, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi), integral = TRUE))), error = function(e) NULL)
    if (is.null(m)) next
    kk <- if (kind == 22) 2 else if (kind == 6) 7 else if (kind == 7) 6 else kind
    v <- as.vector(t(m)); a <- c(n, nk, degree, icp, lo, hi, kk, x, kn); add("sum", a, sum(v)); add("w", a, sum(seq_along(v) * v))
  }
}
# derivatives of naturalSpline (kinds 30, 31) and nsk (32, 33)
for (rep in 1:40) {
  lo <- sample(c(0, -1, 2), 1); hi <- lo + sample(c(1, 3), 1); n <- sample(5:20, 1); nk <- sample(2:4, 1); icp <- rbinom(1, 1, 0.5)
  x <- sort(c(lo, hi, round(runif(n - 2, lo, hi), 4))); kn <- sort(round(runif(nk, lo + 0.05 * (hi - lo), hi - 0.05 * (hi - lo)), 3)); if (anyDuplicated(kn)) next
  for (kind in 30:33) {
    d <- if (kind %in% c(30, 32)) 1 else 2
    m <- tryCatch(suppressWarnings(unclass(if (kind <= 31) naturalSpline(x, knots = kn, intercept = icp == 1, Boundary.knots = c(lo, hi), derivs = d) else nsk(x, knots = kn, intercept = icp == 1, Boundary.knots = c(lo, hi), derivs = d))), error = function(e) NULL); if (is.null(m)) next
    v <- as.vector(t(m)); a <- c(n, nk, 3, icp, lo, hi, kind, x, kn); add("sum", a, sum(v)); add("w", a, sum(seq_along(v) * v))
  }
}
# bernsteinPoly integral (kind 19)
for (rep in 1:40) {
  lo <- sample(c(0, -1, 2), 1); hi <- lo + sample(c(1, 3), 1); n <- sample(5:20, 1); degree <- sample(2:7, 1); icp <- rbinom(1, 1, 0.5)
  x <- sort(c(lo, hi, round(runif(n - 2, lo, hi), 4)))
  m <- tryCatch(unclass(bernsteinPoly(x, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi), integral = TRUE)), error = function(e) NULL); if (is.null(m)) next
  v <- as.vector(t(m)); a <- c(n, 0, degree, icp, lo, hi, 19, x); add("sum", a, sum(v)); add("w", a, sum(seq_along(v) * v))
}
# third derivatives: bSpline (kind 40), mSpline (41) and iSpline (42, the mSpline second derivative)
for (rep in 1:40) {
  lo <- sample(c(0, -1, 2), 1); hi <- lo + sample(c(1, 3), 1); n <- sample(5:20, 1); nk <- sample(0:3, 1); degree <- sample(3:5, 1); icp <- rbinom(1, 1, 0.5)
  x <- sort(c(lo, hi, round(runif(n - 2, lo, hi), 4))); kn <- if (nk > 0) sort(round(runif(nk, lo + 0.05 * (hi - lo), hi - 0.05 * (hi - lo)), 3)) else numeric(0); if (anyDuplicated(kn)) next
  for (kind in 40:42) {
    m <- tryCatch(suppressWarnings(unclass(switch(kind - 39, bSpline(x, knots = kn, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi), derivs = 3), mSpline(x, knots = kn, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi), derivs = 3), iSpline(x, knots = kn, degree = degree, intercept = icp == 1, Boundary.knots = c(lo, hi), derivs = 3)))), error = function(e) NULL); if (is.null(m)) next
    v <- as.vector(t(m)); a <- c(n, nk, degree, icp, lo, hi, kind, x, kn); cases[[length(cases) + 1]] <- case("sum", a, sum(v), rel = 1e-9, abs = 1e-8); cases[[length(cases) + 1]] <- case("w", a, sum(seq_along(v) * v), rel = 1e-9, abs = 1e-8)
  }
}
emit("splines2", "splines2", list(cases))
