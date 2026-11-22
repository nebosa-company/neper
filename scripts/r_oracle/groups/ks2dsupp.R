# ks ksupp in two dimensions: the grid points above the level and their convex hull, summarised order free.
#   args: "ksupp" (n, H row-major 4, cont, which, x row-major...); which: 0 point count, 4 hull area (the vertex set of chull keeps some collinear grid points by its own tolerance and is not compared)
suppressMessages(library(ks))
cases <- list()
add <- function(fn, args, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-13)
rowvec <- function(m) as.vector(t(m))
set.seed(20262011)
for (rep in 1:5) {
  n <- sample(30:80, 1)
  A <- matrix(runif(4, -1, 1), 2, 2)
  x <- round(cbind(rnorm(n), rnorm(n)) %*% A + cbind(rep(c(0, 2), length.out = n), rep(c(0, -1), length.out = n)), 5)
  B <- matrix(runif(4, -0.4, 0.4), 2, 2); H <- crossprod(B) + diag(runif(2, 0.05, 0.3))
  f <- kde(x, H = H, binned = FALSE, compute.cont = FALSE)
  for (ct in c(50, 95)) {
    lev <- contourLevels(f, cont = ct)
    s <- ksupp(f, cont = ct)
    sm <- as.matrix(s); k <- nrow(sm)
    area <- abs(sum(sm[, 1] * sm[c(2:k, 1), 2] - sm[c(2:k, 1), 1] * sm[, 2])) / 2
    vals <- c(sum(f$estimate > lev), k, sum(sm[, 1]), sum(sm[, 2]), area)
    for (w in c(0, 4)) add("ksupp", c(n, rowvec(H), ct, w, rowvec(x)), vals[w + 1])
  }
}
emit("ks2dsupp", "ks", list(cases))
