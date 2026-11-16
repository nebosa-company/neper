# dbscanpkg: kNNdist and lof of the dbscan package.
#   args: (n, d, k or minPts, row index, x row-major n by d...); "knnd" and "lof" answer for that row; "snn" (n, d, k, row, c, x...) is sNN$shared for the c-th nearest neighbour in kNN order (sNN sorts its own ids by shared count); "frcount" and "frsum" (n, d, eps, row, 0, x...)
suppressMessages(library(dbscan))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20262002)
for (rep in 1:20) {
  n <- sample(20:70, 1); d <- sample(2:4, 1); x <- matrix(round(rnorm(n * d), 5), n, d); x[1, ] <- x[1, ] + 4
  k <- sample(2:8, 1); kd <- kNNdist(x, k); lf <- lof(x, minPts = k + 1)
  for (i in sample(n, 6)) { add("knnd", c(n, d, k, i - 1, as.vector(t(x))), kd[i]); add("lof", c(n, d, k + 1, i - 1, as.vector(t(x))), lf[i]) }
  add("lof", c(n, d, k + 1, 0, as.vector(t(x))), lf[1])
}
for (rep in 1:15) {
  n <- sample(20:60, 1); d <- sample(2:3, 1); x <- matrix(round(rnorm(n * d), 5), n, d); k <- sample(3:8, 1); s <- sNN(x, k = k); eps <- runif(1, 0.3, 1.2); fr <- frNN(x, eps = eps)
  for (i in sample(n, 5)) {
    c <- sample(k, 1); jj <- kNN(x, k = k)$id[i, c]; add("snn", c(n, d, k, i - 1, c - 1, as.vector(t(x))), s$shared[i, which(s$id[i, ] == jj)])
    add("frcount", c(n, d, eps, i - 1, 0, as.vector(t(x))), length(fr$id[[i]])); add("frsum", c(n, d, eps, i - 1, 0, as.vector(t(x))), sum(fr$dist[[i]]))
  }
}
emit("dbscanpkg", "dbscan", list(cases))
