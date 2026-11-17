# lapack_exact: eigen(symmetric = TRUE) (LAPACK dsyevr) and svd() (LAPACK dgesdd), compared vector for vector, signs included.
# The matrices come from closed forms of (kind, rows, cols, seed) that the fixture reproduces: a Lehmer generator
# x <- x * 48271 mod 2147483647 (exact in doubles) feeds every kind.
#   "eig" args: kind, n, seed, mode, matrix sum, matrix sum of squares, then R's values (n) and either the vectors
#         column by column (mode 0) or one sign-sensitive weighted sum per vector (mode 1)
#   "svd" args: kind, nr, nc, seed, mode, matrix sum, matrix sum of squares, then d (k), u (nr by k) and v (nc by k)
#         column by column (mode 0), or d and one weighted sum per column of u then of v (mode 1); k = min(nr, nc)
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 0, abs = 1e-12)

lehmer <- function(seed, count) {
  x <- (seed * 7919 + 12345) %% 2147483647
  out <- numeric(count)
  for (i in seq_len(count)) { x <- (x * 48271) %% 2147483647; out[i] <- x / 2147483647 }
  out
}
wts <- function(n) (((0:(n - 1)) * 37) %% 101) / 50 - 1 + 0.01
colw <- function(m) as.numeric(crossprod(wts(nrow(m)), m))

symmat <- function(kind, n, seed) {
  if (kind == 0) { B <- matrix(lehmer(seed, n * n) - 0.5, n, n); return((B + t(B)) / 2) }
  if (kind == 1) { B <- matrix(floor(lehmer(seed, n * n) * 11) - 5, n, n); return(B + t(B)) }
  if (kind == 2) { r <- max(1, n %/% 3); C <- matrix(floor(lehmer(seed, n * r) * 7) - 3, n, r); return(C %*% t(C)) }
  if (kind == 3) { C <- matrix(floor(lehmer(seed, n * 2) * 7) - 3, n, 2); A <- C %*% t(C); for (i in 1:n) A[i, i] <- A[i, i] + 3; return(A) }
  if (kind == 4) { A <- matrix(0, n, n); for (i in 1:n) for (j in 1:n) A[i, j] <- if (i == j) 2 else if (abs(i - j) == 1) -1 else 0; return(A) }
  if (kind == 5) { A <- matrix(0, n, n); for (i in 1:n) A[i, i] <- (i * i) %% 5; return(A) }
  matrix(1, n, n)
}
genmat <- function(kind, nr, nc, seed) {
  if (kind == 0) return(matrix(lehmer(seed, nr * nc) - 0.5, nr, nc))
  if (kind == 1) return(matrix(floor(lehmer(seed, nr * nc) * 11) - 5, nr, nc))
  if (kind == 2) {
    r <- max(1, min(nr, nc) %/% 2)
    C <- matrix(floor(lehmer(seed, nr * r) * 7) - 3, nr, r); D <- matrix(floor(lehmer(seed + 1, r * nc) * 7) - 3, r, nc)
    return(C %*% D)
  }
  if (kind == 3) { A <- matrix(0, nr, nc); for (i in 1:min(nr, nc)) A[i, i] <- 2; return(A) }
  A <- matrix(lehmer(seed, nr * nc) - 0.5, nr, nc); A[, 1] <- 0; A
}

for (kind in 0:6) for (n in c(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15, 17, 20, 24, 28, 33, 40)) {
  A <- symmat(kind, n, kind * 1000 + n); e <- eigen(A, symmetric = TRUE)
  add("eig", c(kind, n, kind * 1000 + n, 0, sum(A), sum(A * A), e$values, as.numeric(e$vectors)), 0)
}
for (kind in c(0, 1, 4)) for (n in c(50, 64, 130)) {
  A <- symmat(kind, n, kind * 1000 + n); e <- eigen(A, symmetric = TRUE)
  add("eig", c(kind, n, kind * 1000 + n, 1, sum(A), sum(A * A), e$values, colw(e$vectors)), 0)
}

shapes <- c(1, 2, 3, 5, 8, 13, 21, 30)
for (kind in 0:2) for (nr in shapes) for (nc in shapes) {
  seed <- kind * 100000 + nr * 100 + nc; A <- genmat(kind, nr, nc, seed); s <- svd(A)
  add("svd", c(kind, nr, nc, seed, 0, sum(A), sum(A * A), s$d, as.numeric(s$u), as.numeric(s$v)), 0)
}
for (kind in 3:4) for (sh in list(c(1, 6), c(6, 1), c(4, 4), c(9, 5), c(5, 9), c(12, 7), c(7, 12), c(20, 20), c(30, 11), c(11, 30), c(40, 40), c(45, 16), c(16, 45), c(31, 31))) {
  nr <- sh[1]; nc <- sh[2]; seed <- kind * 100000 + nr * 100 + nc; A <- genmat(kind, nr, nc, seed); s <- svd(A)
  add("svd", c(kind, nr, nc, seed, 0, sum(A), sum(A * A), s$d, as.numeric(s$u), as.numeric(s$v)), 0)
}
for (kind in 0:1) for (sh in list(c(40, 12), c(12, 40), c(26, 26), c(60, 20), c(20, 60), c(50, 50), c(150, 40), c(40, 150), c(130, 130))) {
  nr <- sh[1]; nc <- sh[2]; seed <- kind * 100000 + nr * 100 + nc; A <- genmat(kind, nr, nc, seed); s <- svd(A)
  add("svd", c(kind, nr, nc, seed, 1, sum(A), sum(A * A), s$d, colw(s$u), colw(s$v)), 0)
}
emit("lapack_exact", character(), list(cases))
