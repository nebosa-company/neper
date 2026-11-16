# dbscanpkg: kNNdist and lof of the dbscan package.
#   args: (n, d, k or minPts, row index, x row-major n by d...); "knnd" and "lof" answer for that row
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
emit("dbscanpkg", "dbscan", list(cases))
