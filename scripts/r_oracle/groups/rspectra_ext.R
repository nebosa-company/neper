# RSpectra svds with nu / nv below k (mode 2) and eigs_sym with retvec = FALSE (mode 3), sign-exact position-weighted sums at R's default tol, niter and nops (kept only where R reproduces them on the matrix perturbed at the rounding level).
suppressMessages(library(RSpectra))
cases <- list()
set.seed(20262411)
add <- function(args, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case("rspectra_ext", args, want, rel = rel, abs = 1e-11)
w <- function(M) sum(M * seq_along(M))
ws <- function(M) sum(abs(colSums(M * seq_len(nrow(M)))) * seq_len(ncol(M)))
whichs <- c("LM", "LA", "SM", "SA", "BE")
jig <- function(M) M * (1 + 1e-11 * matrix(rnorm(length(M)), nrow(M)))
# 2 svds with nu / nv below k: (2, m, n, k, nu, nv, kind, x[m * n] column-major); kind 0 d, 1 u, 2 v, 3 niter, 4 nops, 5 length(u), 6 length(v) (all at R's default tol and maxitr)
for (rep in 1:14) {
  m <- sample(18:30, 1); n <- sample(9:14, 1); if (rep %% 3 == 0) { t <- m; m <- n; n <- t }
  k <- sample(3:5, 1); nu <- sample(0:k, 1); nv <- sample(0:k, 1)
  X <- matrix(round(rnorm(m * n) * runif(n, 0.5, 2), 4), m)
  run <- function(M) tryCatch(suppressWarnings(svds(M, k, nu = nu, nv = nv)), error = function(e) NULL)
  r <- run(X)
  if (is.null(r) || length(r$d) < k) next
  a <- function(kind) c(2, m, n, k, nu, nv, kind, as.vector(X))
  add(a(0), w(r$d)); add(a(5), length(r$u), 0); add(a(6), length(r$v), 0)
  r2 <- run(jig(X))
  if (!is.null(r2) && r2$niter == r$niter && r2$nops == r$nops && (nu == 0 || max(abs(r2$u - r$u)) < 1e-4) && (nv == 0 || max(abs(r2$v - r$v)) < 1e-4)) {
    if (nu > 0) add(a(1), ws(r$u))
    if (nv > 0) add(a(2), ws(r$v))
    add(a(3), r$niter, 0); add(a(4), r$nops, 0)
  }
}
# 3 eigs_sym with retvec = FALSE: (3, n, k, which, kind, A[n * n] column-major); kind 0 values, 1 niter, 2 nops (R returns no vectors; the port has no retvec switch, its vectors are simply not read)
for (rep in 1:10) {
  n <- sample(20:28, 1); k <- sample(2:5, 1); wi <- (rep - 1) %% 5 + 1
  Z <- matrix(round(rnorm(n * n), 3), n); A <- round((Z + t(Z)) / 2, 4)
  r <- tryCatch(suppressWarnings(eigs_sym(A, k, which = whichs[wi], opts = list(retvec = FALSE))), error = function(e) NULL)
  if (is.null(r) || r$nconv < k) next
  a <- function(kind) c(3, n, k, wi - 1, kind, as.vector(A))
  add(a(0), w(r$values));
  B <- A; B[lower.tri(B)] <- jig(A)[lower.tri(B)]
  r2 <- tryCatch(suppressWarnings(eigs_sym(B, k, which = whichs[wi], opts = list(retvec = FALSE))), error = function(e) NULL)
  if (!is.null(r2) && r2$niter == r$niter && r2$nops == r$nops) { add(a(1), r$niter, 0); add(a(2), r$nops, 0) }
}
emit("rspectra_ext", "RSpectra", list(cases))
