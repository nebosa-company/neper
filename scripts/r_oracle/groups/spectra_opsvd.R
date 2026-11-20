# RSpectra: svds with a function operator A(x) = B x and A'(y) = B' y for a banded-plus-rank-one B (m by n). Args: (m, n, k, part, d[n] diagonal, u[m], w[n]): B = diag-like(d) + u w';
# part 0 values (sum of d_j * position), 1 left vectors, 2 right vectors (sign-aligned on the left vector's largest component, sum of entry * column-major position).
suppressMessages(library(RSpectra))
cases <- list()
set.seed(20262355)
add <- function(a, want) cases[[length(cases) + 1]] <<- case("os", a, want, rel = 1e-9, abs = 1e-11)
for (rep in 1:20) {
  m <- sample(20:40, 1); n <- sample(10:18, 1); k <- sample(2:4, 1); dg <- round(rnorm(n), 4); u <- round(rnorm(m) * 0.5, 4); w <- round(rnorm(n) * 0.5, 4)
  Bm <- function(x, args) { y <- numeric(m); y[1:n] <- dg * x; y + u * sum(w * x) }
  Bt <- function(y, args) { x <- dg * y[1:n]; x + w * sum(u * y) }
  B <- matrix(0, m, n); B[cbind(1:n, 1:n)] <- dg; B <- B + tcrossprod(u, w)
  sv <- svd(B)$d; if (abs(sv[k] - sv[k + 1]) < 1e-6) next
  o <- svds(Bm, k, Atrans = Bt, dim = c(m, n), opts = list(tol = 1e-14, maxitr = 5000))
  s <- apply(o$u, 2, function(x) sign(x[which.max(abs(x))])); U <- t(t(o$u) * s); V <- t(t(o$v) * s)
  a <- function(part) c(m, n, k, part, dg, u, w)
  add(a(0), sum(o$d * seq_along(o$d))); add(a(1), sum(as.vector(U) * seq_along(U))); add(a(2), sum(as.vector(V) * seq_along(V)))
}
emit("spectra_opsvd", "RSpectra", list(cases))
