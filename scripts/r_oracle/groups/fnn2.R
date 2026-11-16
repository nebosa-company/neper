# FNN get.knn and knn.reg (brute), continuous data so no ties.
#   args: (kind, n, p, m, k, X[n*p] col-major, Y[m*p] col-major (kind 2 test set), y[n], q)
#   kind 0 get.knn: q 0 sum idx 1 weighted idx 2 sum dist 3 weighted dist ; kind 1 knn.reg LOO: q 0 sum pred 1 weighted pred 2 PRESS 3 R2 ; kind 2 knn.reg test: q 0 sum 1 weighted
suppressMessages(library(FNN))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("v", args, want, rel = 1e-9, abs = 1e-11)
set.seed(20261118)
for (rep in 1:30) {
  n <- sample(30:120, 1); p <- sample(1:4, 1); m <- sample(10:60, 1); k <- sample(1:8, 1)
  X <- matrix(rnorm(n * p), n, p); Ym <- matrix(rnorm(m * p), m, p); y <- round(X[, 1] + rnorm(n), 4)
  base <- function(kind) c(kind, n, p, m, k, X, Ym, y)
  g <- get.knn(X, k, "brute"); ix <- as.vector(g$nn.index); ds <- as.vector(g$nn.dist)
  add(c(base(0), 0), sum(ix)); add(c(base(0), 1), sum(seq_along(ix) * ix)); add(c(base(0), 2), sum(ds)); add(c(base(0), 3), sum(seq_along(ds) * ds))
  r <- knn.reg(X, y = y, k = k, algorithm = "brute")
  add(c(base(1), 0), sum(r$pred)); add(c(base(1), 1), sum(seq_along(r$pred) * r$pred)); add(c(base(1), 2), r$PRESS); add(c(base(1), 3), r$R2Pred)
  r2 <- knn.reg(X, Ym, y, k = k, algorithm = "brute")
  add(c(base(2), 0), sum(r2$pred)); add(c(base(2), 1), sum(seq_along(r2$pred) * r2$pred))
}
emit("fnn2", "FNN", list(cases))
