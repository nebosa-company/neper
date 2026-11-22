# ks, two dimensions: the gridded kde(x, H), contourLevels(kde, cont) and rkde under set.seed.
#   args: "kdegrid" (n, H row-major 4, qi, qj, x row-major...); "kdecont" (n, H4, cont, x...);
#         "rkde2" (seed, n, H4, size, pos, x...); "rkde1" (seed, n, h, size, pos, x...)
suppressMessages(library(ks))
cases <- list()
add <- function(fn, args, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-13)
rowvec <- function(m) as.vector(t(m))
set.seed(20262009)
for (rep in 1:6) {
  n <- sample(30:70, 1)
  A <- matrix(runif(4, -1, 1), 2, 2)
  x <- round(cbind(rnorm(n), rnorm(n)) %*% A + cbind(rep(c(0, 2), length.out = n), rep(c(0, -1), length.out = n)), 5)
  B <- matrix(runif(4, -0.4, 0.4), 2, 2); H <- crossprod(B) + diag(runif(2, 0.05, 0.3))
  f <- kde(x, H = H, binned = FALSE, compute.cont = FALSE)
  est <- f$estimate
  pos <- which(est > 0, arr.ind = TRUE)
  pick <- pos[sample(nrow(pos), 8), , drop = FALSE]
  for (k in 1:8) add("kdegrid", c(n, rowvec(H), pick[k, 1] - 1, pick[k, 2] - 1, rowvec(x)), est[pick[k, 1], pick[k, 2]])
  for (ct in c(1, 5, 25, 50, 75, 95, 99)) add("kdecont", c(n, rowvec(H), ct, rowvec(x)), unname(contourLevels(f, cont = ct, approx = TRUE)))
}
for (n in c(60, 250)) {
  x <- round(cbind(rnorm(n), rnorm(n, 1, 2)), 5)
  B <- matrix(runif(4, -0.4, 0.4), 2, 2); H <- crossprod(B) + diag(runif(2, 0.05, 0.3))
  f <- kde(x, H = H, binned = FALSE, compute.cont = FALSE)
  for (seed in 1:2) {
    set.seed(seed); r <- rkde(25, f)
    for (pos in c(0, 1, 2, 17, 30, 49)) add("rkde2", c(seed, n, rowvec(H), 25, pos, rowvec(x)), rowvec(r)[pos + 1])
    h <- 0.3
    f1 <- kde(x[, 1], h = h, binned = FALSE, compute.cont = FALSE)
    set.seed(seed); r1 <- rkde(25, f1)
    for (pos in c(0, 1, 7, 24)) add("rkde1", c(seed, n, h, 25, pos, x[, 1]), r1[pos + 1])
  }
}
emit("ks2dkde", "ks", list(cases))
