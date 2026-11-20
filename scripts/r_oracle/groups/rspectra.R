# RSpectra::eigs_sym and svds (Spectra's implicitly restarted Lanczos), sign-exact position-weighted sums, niter and nops. Args by mode a[1]:
# 0 eigs_sym: (0, n, k, which 0 LM 1 LA 2 SM 3 SA 4 BE, hasSigma, sigma, kind, A[n * n] column-major); kind 0 values, 1 vectors (column-sign free), 2 niter, 3 nops
# 1 svds: (1, m, n, k, center, scale, kind, x[m * n] column-major, center vector[n], scale vector[n]); kind 0 d, 1 u, 2 v (column-sign free), 3 niter, 4 nops
# The vectors, niter and nops of a case are kept only when R itself reproduces them (signs included) on the matrix perturbed at the rounding level:
# where the restarts amplify rounding (an interior eigenvalue, a tight cluster) the path follows the order of the reductions, which only the same BLAS and Eigen build repeat.
suppressMessages(library(RSpectra))
cases <- list()
set.seed(20262403)
add <- function(args, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case("rspectra", args, want, rel = rel, abs = 1e-11)
w <- function(M) sum(M * seq_along(M))
# column-wise sign-free: R's binary and a fresh build of the same Spectra and Eigen sources differ in the global sign of a few Ritz vector sets (rounding-level reduction order), so vectors are compared up to the sign of each column
ws <- function(M) sum(abs(colSums(M * seq_len(nrow(M)))) * seq_len(ncol(M)))
whichs <- c("LM", "LA", "SM", "SA", "BE")
jig <- function(M) M * (1 + 1e-11 * matrix(rnorm(length(M)), nrow(M)))
for (rep in 1:25) {
  n <- sample(20:28, 1); k <- sample(2:5, 1); wi <- (rep - 1) %% 5 + 1
  Z <- matrix(round(rnorm(n * n), 3), n); A <- round((Z + t(Z)) / 2, 4)
  hs <- as.integer(rep %% 4 == 0); sg <- if (hs) round(runif(1, -1, 1), 3) else 0
  if (hs && wi == 5) wi <- 1
  run <- function(M) tryCatch(suppressWarnings(eigs_sym(M, k, which = whichs[wi], sigma = if (hs) sg else NULL)), error = function(e) NULL)
  r <- run(A)
  if (is.null(r) || r$nconv < k) next
  a <- function(kind) c(0, n, k, wi - 1, hs, sg, kind, as.vector(A))
  add(a(0), w(r$values))
  B <- A; B[lower.tri(B)] <- jig(A)[lower.tri(B)]; r2 <- run(B)
  if (!is.null(r2) && r2$nconv == k && r2$niter == r$niter && r2$nops == r$nops && max(abs(r2$vectors - r$vectors)) < 1e-4) {
    add(a(1), ws(r$vectors)); add(a(2), r$niter, 0); add(a(3), r$nops, 0)
  }
}
for (rep in 1:18) {
  m <- sample(18:30, 1); n <- sample(9:14, 1); if (rep %% 3 == 0) { t <- m; m <- n; n <- t }
  k <- sample(2:5, 1); cen <- as.integer(rep %% 2 == 0); sc <- as.integer(rep %% 4 == 0)
  X <- matrix(round(rnorm(m * n) * runif(n, 0.5, 2), 4), m)
  ctr <- if (cen) colMeans(X) else rep(0, n)
  scl <- if (sc) sqrt(colSums((X - rep(ctr, each = m))^2)) else rep(1, n)
  opts <- list(); if (cen) opts$center <- ctr; if (sc) opts$scale <- scl
  run <- function(M) tryCatch(suppressWarnings(svds(M, k, opts = opts)), error = function(e) NULL)
  r <- run(X)
  if (is.null(r) || length(r$d) < k) next
  a <- function(kind) c(1, m, n, k, cen, sc, kind, as.vector(X), ctr, scl)
  add(a(0), w(r$d))
  r2 <- run(jig(X))
  if (!is.null(r2) && r2$niter == r$niter && r2$nops == r$nops && max(abs(r2$u - r$u)) < 1e-4 && max(abs(r2$v - r$v)) < 1e-4) {
    add(a(1), ws(r$u)); add(a(2), ws(r$v)); add(a(3), r$niter, 0); add(a(4), r$nops, 0)
  }
}
emit("rspectra", "RSpectra", list(cases))
