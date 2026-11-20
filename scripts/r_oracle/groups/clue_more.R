# clue: soft-partition dissimilarities and agreements beyond euclidean, and ultrametric objects.
#   "softm" (kind, n, kx, ky, U row-major n x kx, V row-major n x ky): kind 0 euclidean, 1 manhattan, 2 comemberships, 3 GV1 (cl_dissimilarity),
#       4 euclidean, 5 manhattan, 6 angle, 7 diag (cl_agreement); kx and ky differ in about half of the cases (the smaller partition gets zero classes)
#   "ultra" (kind, n, U full n x n, V full n x n): cl_dissimilarity of as.cl_ultrametric objects, kind 0 euclidean, 1 manhattan, 2 cophenetic, 3 gamma, 4 Chebyshev;
#       cl_agreement kind 5 cophenetic, 6 angle, 7 gamma, 8 euclidean, 9 manhattan
suppressMessages(library(clue))
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-10)
set.seed(20262481)
dis <- c("euclidean", "manhattan", "comemberships", "GV1")
agr <- c("euclidean", "manhattan", "angle", "diag")
rsoft <- function(n, k) { M <- matrix(rexp(n * k), n, k); M / rowSums(M) }
for (rep in 1:28) {
  n <- sample(8:30, 1); kx <- sample(2:5, 1); ky <- if (rep %% 2 == 0) kx else sample(2:5, 1)
  U <- rsoft(n, kx); V <- rsoft(n, ky)
  px <- as.cl_partition(U); py <- as.cl_partition(V)
  a <- c(n, kx, ky, as.vector(t(U)), as.vector(t(V)))
  for (m in 1:4) {
    add("softm", c(m - 1, a), as.numeric(cl_dissimilarity(px, py, method = dis[m])))
    add("softm", c(m + 3, a), as.numeric(cl_agreement(px, py, method = agr[m])))
  }
}
meth <- c("ward.D", "single", "complete", "average", "mcquitty", "ward.D2")
ultra <- function(n) {
  x <- matrix(round(rnorm(n * 2) * 3, 3), n, 2)
  round(as.matrix(cophenetic(hclust(dist(x), sample(meth, 1)))), 5)
}
for (rep in 1:28) {
  n <- sample(5:12, 1)
  U <- ultra(n); V <- ultra(n)
  uu <- as.cl_ultrametric(as.dist(U)); vv <- as.cl_ultrametric(as.dist(V))
  a <- c(n, as.vector(U), as.vector(V))
  for (kd in 0:4) add("ultra", c(kd, a), as.numeric(cl_dissimilarity(uu, vv, method = c("euclidean", "manhattan", "cophenetic", "gamma", "Chebyshev")[kd + 1])))
  for (kd in 5:9) add("ultra", c(kd, a), as.numeric(cl_agreement(uu, vv, method = c("cophenetic", "angle", "gamma", "euclidean", "manhattan")[kd - 4])))
}
emit("clue_more", "clue", list(cases))
