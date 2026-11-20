# irlba::irlba on a sparse Matrix (dgCMatrix) input at tol 1e-12: R runs its compiled sparse path (its own iterates, so iter, mprod and the start differ from the R-code path the port follows); the converged d, u and v agree,
# the vectors sign-aligned (largest component of u positive). Position-weighted sums.
# Args: (m, n, nv, work, smallest, seed, kind 0 d 1 u 2 v, nnz, i[nnz] 0-based, j[nnz] 0-based, x[nnz], cen, sc, center[n], scale[n]); cen and sc flag the centre and scale vectors passed to irlba.
suppressMessages({library(irlba); library(Matrix)})
cases <- list()
set.seed(20262611)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("irlbasp", args, want, rel = 1e-9, abs = 1e-11)
w <- function(M) sum(as.vector(M) * seq_along(M))
for (rep in 1:24) {
  m <- sample(30:60, 1); n <- sample(12:20, 1); if (rep %% 4 == 0) { t <- m; m <- n; n <- t }
  nv <- sample(2:4, 1); work <- nv + sample(3:7, 1); smallest <- as.integer(rep %% 5 == 0)
  A <- rsparsematrix(m, n, density = 0.3, rand.x = function(q) round(rnorm(q), 4))
  sd1 <- sample(1:100000, 1); set.seed(sd1)
  cen <- as.integer(rep > 16 && rep %% 2 == 1); sc <- as.integer(rep > 16 && rep %% 3 != 1)
  cv <- Matrix::colMeans(A); sv <- sqrt(Matrix::colSums((A - rep(cv, each = m))^2) / (m - 1)); if (!cen) cv <- rep(0, n); if (!sc) sv <- rep(1, n)
  ia <- list(A = A, nv = nv, work = work, smallest = smallest == 1, tol = 1e-12, maxit = 5000); if (cen) ia$center <- cv; if (sc) ia$scale <- sv
  r <- tryCatch(suppressWarnings(do.call(irlba, ia)), error = function(e) NULL); if (is.null(r)) next
  s <- summary(A)
  a <- function(kind) c(m, n, nv, work, smallest, sd1, kind, nrow(s), s$i - 1, s$j - 1, s$x, cen, sc, cv, sv)
  sg <- apply(r$u, 2, function(x) sign(x[which.max(abs(x))]))
  add(a(0), w(r$d)); add(a(1), w(t(t(r$u) * sg))); add(a(2), w(t(t(r$v) * sg)))
}
emit("spectra_irlba_sp", c("irlba", "Matrix"), list(cases))
