# ks in one to four dimensions with H given: Hns, kde at points, gridded kde (exact and binned) and contourLevels.
#   "hns" (d, n, r, entry, x row-major...); "kdeat" (d, n, H d*d, point d, x...);
#   "kdegrid" (d, n, binned, m, H, flat 0-based grid index, x...); "kdecont" (d, n, binned, m, H, cont, x...)
suppressMessages(library(ks))
cases <- list()
add <- function(fn, args, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-13)
rowvec <- function(m) as.vector(t(m))
spd <- function(d) { B <- matrix(runif(d * d, -0.4, 0.4), d, d); crossprod(B) + diag(runif(d, 0.05, 0.3), d) }
mkx <- function(n, d) { A <- matrix(runif(d * d, -1, 1), d, d); round(matrix(rnorm(n * d), n, d) %*% A + matrix(rep(0:(d - 1), each = n) * 0.5, n, d), 5) }
msize <- function(d, binned) if (binned) c(401, 151, 31, 15)[d] else c(401, 151, 51, 21)[d]
set.seed(20262011)
for (d in 1:4) for (rep in 1:3) {
  n <- sample(30:70, 1)
  x <- mkx(n, d); H <- spd(d)
  xx <- if (d == 1) as.vector(x) else x
  if (d > 1) for (r in c(0, 2)) { Hn <- Hns(x, deriv.order = r); for (e in sample(d * d, 3)) add("hns", c(d, n, r, e - 1, rowvec(x)), rowvec(Hn)[e]) }
  pts <- matrix(rnorm(3 * d, 0.3, 1), 3, d)
  for (k in 1:3) {
    f <- if (d == 1) kde(xx, h = sqrt(H[1, 1]), binned = FALSE, eval.points = pts[k, 1]) else kde(x, H = H, binned = FALSE, eval.points = pts[k, , drop = FALSE])
    add("kdeat", c(d, n, rowvec(H), pts[k, ], rowvec(x)), as.vector(f$estimate))
  }
  for (binned in c(FALSE, TRUE)) {
    f <- if (d == 1) kde(xx, h = sqrt(H[1, 1]), binned = binned, compute.cont = FALSE) else kde(x, H = H, binned = binned, compute.cont = FALSE)
    est <- as.vector(f$estimate)
    pos <- which(est > 1e-6)
    for (k in sample(pos, 6)) add("kdegrid", c(d, n, binned, msize(d, binned), rowvec(H), k - 1, rowvec(x)), est[k])
    for (ct in c(5, 50, 95)) add("kdecont", c(d, n, binned, msize(d, binned), rowvec(H), ct, rowvec(x)), unname(contourLevels(f, cont = ct, approx = TRUE)))
    for (ct in c(50, 95)) {
      M <- as.matrix(ksupp(f, cont = ct, convex.hull = FALSE))
      add("ksupp", c(d, n, binned, msize(d, binned), rowvec(H), ct, 0, rowvec(x)), nrow(M))
      for (j in 1:d) add("ksupp", c(d, n, binned, msize(d, binned), rowvec(H), ct, j, rowvec(x)), sum(M[, j]))
    }
  }
}
emit("ksnd", "ks", list(cases))
