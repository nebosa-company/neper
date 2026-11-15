# The Matrix package's sparse operations on seeded matrices: A %*% B (dense B), t(A) %*% B, the
# sparse product crossprod(A), chol(A) (upper factor, natural order) and solve(A, b) for a symmetric
# positive-definite A. A is given as triplets (0-based).
#   args: (nrow, ncol, nnz, i..., j..., x..., k, b...)   b is a dense (ncol or nrow) by k column-major matrix
#   "sp_mult" (nrow*k), "sp_tmult" (ncol*k, b has nrow rows), "sp_cross" (ncol*ncol), "sp_chol" (n*n), "sp_solve" (n*k)
library(Matrix)
set.seed(20261115)
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-10, abs = 1e-12)
vec <- function(name, args, v) {
  add(paste0("len:", name), args, length(v))
  for (i in seq_along(v)) add(paste0("v:", name), c(args, i - 1), v[i])
}
trip <- function(m) { s <- summary(m); list(i = s$i - 1, j = s$j - 1, x = s$x) }
rand_sparse <- function(nr, nc, dens) {
  hit <- which(matrix(runif(nr * nc) < dens, nr, nc), arr.ind = TRUE)
  if (nrow(hit) == 0) hit <- matrix(c(1, 1), 1, 2)
  extra <- hit[sample(nrow(hit), min(3, nrow(hit))), , drop = FALSE]
  all <- rbind(hit, extra)   # duplicate triplets are summed
  sparseMatrix(i = all[, 1], j = all[, 2], x = round(rnorm(nrow(all)), 3), dims = c(nr, nc))
}
for (k in 1:30) {
  nr <- sample(2:9, 1); nc <- sample(2:9, 1); kk <- sample(1:3, 1)
  A <- rand_sparse(nr, nc, runif(1, 0.1, 0.5))
  t3 <- trip(A)
  B <- matrix(round(rnorm(nc * kk), 3), nc, kk)
  a <- c(nr, nc, length(t3$x), t3$i, t3$j, t3$x, kk, B)
  vec("sp_mult", a, as.numeric(as.matrix(A %*% B)))
  C <- matrix(round(rnorm(nr * kk), 3), nr, kk)
  a2 <- c(nr, nc, length(t3$x), t3$i, t3$j, t3$x, kk, C)
  vec("sp_tmult", a2, as.numeric(as.matrix(t(A) %*% C)))
  vec("sp_cross", c(nr, nc, length(t3$x), t3$i, t3$j, t3$x, 0), as.numeric(as.matrix(crossprod(A))))
}
for (k in 1:30) {
  n <- sample(2:12, 1); kk <- sample(1:3, 1)
  M <- rand_sparse(n + 2, n, runif(1, 0.1, 0.4))
  S <- forceSymmetric(crossprod(M) + Diagonal(n, runif(n, 0.5, 2)))
  S <- as(as(S, "generalMatrix"), "CsparseMatrix")
  t3 <- trip(S)
  b <- matrix(round(rnorm(n * kk), 3), n, kk)
  a <- c(n, n, length(t3$x), t3$i, t3$j, t3$x, kk, b)
  R <- as.matrix(chol(forceSymmetric(S), pivot = FALSE))
  vec("sp_chol", a, as.numeric(R))
  vec("sp_solve", a, as.numeric(as.matrix(solve(S, b))))
}
emit("sparse", "Matrix", list(cases))
