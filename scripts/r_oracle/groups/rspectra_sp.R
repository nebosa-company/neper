# RSpectra::svds on a sparse Matrix (dgCMatrix) input with opts center and scale: d, u, v (column-sign free position-weighted sums), niter and nops. R's sparse path takes the dense path's iterates,
# so the cases are kept as in the rspectra group only where R reproduces niter and nops on the matrix perturbed at the rounding level.
# Args: (m, n, k, cen, sc, kind 0 d 1 u 2 v 3 niter 4 nops, nnz, i[nnz] 0-based, j[nnz] 0-based, x[nnz], center vector[n], scale vector[n]).
suppressMessages({library(RSpectra); library(Matrix)})
cases <- list()
set.seed(20262741)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("rspsp", args, want, rel = 1e-9, abs = 1e-11)
w <- function(M) sum(M * seq_along(M))
ws <- function(M) sum(abs(colSums(M * seq_len(nrow(M)))) * seq_len(ncol(M)))
for (rep in 1:18) {
  m <- sample(40:70, 1); n <- sample(30:50, 1); if (rep %% 3 == 0) { t <- m; m <- n; n <- t }
  k <- sample(3:6, 1); cen <- as.integer(rep %% 2 == 0); sc <- as.integer(rep %% 4 == 0 || rep %% 5 == 0)
  A <- rsparsematrix(m, n, density = 0.3, rand.x = function(q) round(rnorm(q), 4))
  ctr <- if (cen) as.numeric(Matrix::colMeans(A)) else rep(0, n)
  scl <- if (sc) sqrt(colSums((as.matrix(A) - rep(ctr, each = m))^2)) else rep(1, n)
  opts <- list(); if (cen) opts$center <- ctr; if (sc) opts$scale <- scl
  run <- function(M) tryCatch(suppressWarnings(svds(M, k, opts = opts)), error = function(e) NULL)
  r <- run(A)
  if (is.null(r) || length(r$d) < k) next
  B <- A; B@x <- B@x * (1 + 1e-11 * rnorm(length(B@x))); r2 <- run(B)
  if (is.null(r2) || r2$niter != r$niter || r2$nops != r$nops || max(abs(r2$u - r$u)) > 1e-4 || max(abs(r2$v - r$v)) > 1e-4) next
  s <- summary(A)
  a <- function(kind) c(m, n, k, cen, sc, kind, nrow(s), s$i - 1, s$j - 1, s$x, ctr, scl)
  add(a(0), w(r$d)); add(a(1), ws(r$u)); add(a(2), ws(r$v)); add(a(3), r$niter); add(a(4), r$nops)
}
emit("rspectra_sp", c("RSpectra", "Matrix"), list(cases))
