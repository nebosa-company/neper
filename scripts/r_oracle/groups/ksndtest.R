# ks kde.test for two samples in 3 and 4 dimensions (H1, H2 given) and rkde in 3 and 4 dimensions.
#   args: "ktn" (d, n1, n2, H1 row-major d*d, H2 row-major d*d, v1, v2, which, x1 row-major, x2 row-major)
#         v1 = v2 = -1: the default var.fhat (3-d only; R's kdde has no 4-d grid so 4-d always gives var.fhat1, var.fhat2)
#         which: 0 Tstat, 1 zstat, 2 pvalue, 3 var, 4 var.fhat1, 5 mean
#         "rkden" (seed, n, d, H d*d, size, pos, x row-major)
suppressMessages(library(ks))
cases <- list()
add <- function(fn, args, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-13)
rowvec <- function(m) as.vector(t(m))
spd <- function(d) { B <- matrix(runif(d * d, -0.4, 0.4), d, d); crossprod(B) + diag(runif(d, 0.05, 0.3)) }
set.seed(20262011)
for (d in 3:4) for (rep in 1:3) {
  n1 <- sample(25:50, 1); n2 <- sample(25:50, 1)
  x1 <- round(matrix(rnorm(n1 * d), n1, d), 5); x2 <- round(matrix(rnorm(n2 * d, 0.3), n2, d) %*% diag(runif(d, 0.8, 1.3)), 5)
  H1 <- spd(d); H2 <- spd(d)
  v1 <- runif(1, 0.001, 0.01); v2 <- runif(1, 0.001, 0.01)
  r <- kde.test(x1, x2, H1 = H1, H2 = H2, var.fhat1 = v1, var.fhat2 = v2)
  vals <- c(r$Tstat, r$zstat, r$pvalue, r$var, r$var.fhat1, r$mean)
  for (w in 0:5) add("ktn", c(d, n1, n2, rowvec(H1), rowvec(H2), v1, v2, w, rowvec(x1), rowvec(x2)), vals[w + 1])
  if (d == 3) {
    r <- kde.test(x1, x2, H1 = H1, H2 = H2)
    vals <- c(r$Tstat, r$zstat, r$pvalue, r$var, r$var.fhat1, r$mean)
    for (w in 0:5) add("ktn", c(d, n1, n2, rowvec(H1), rowvec(H2), -1, -1, w, rowvec(x1), rowvec(x2)), vals[w + 1])
  }
}
for (d in 3:4) {
  n <- 40
  x <- round(matrix(rnorm(n * d), n, d), 5)
  H <- spd(d)
  f <- kde(x, H = H, binned = FALSE, compute.cont = FALSE, eval.points = x[1:2, , drop = FALSE])
  for (seed in 1:2) {
    set.seed(seed); r <- rkde(25, f)
    for (pos in c(0, 1, 2, 17, 40, 74)) add("rkden", c(seed, n, d, rowvec(H), 25, pos, rowvec(x)), rowvec(r)[pos + 1])
  }
}
emit("ksndtest", "ks", list(cases))
