# RSpectra: svds with a function operator A(x) = B x and A'(y) = B' y for a banded-plus-rank-one B (m by n). Args: (m, n, k, d[min(m,n)] diagonal, u[m], w[n]): B = diag-like(d) + u w'; sum of d_j * position.
suppressMessages(library(RSpectra))
cases <- list()
set.seed(20262355)
for (rep in 1:20) {
  m <- sample(20:40, 1); n <- sample(10:18, 1); k <- sample(2:4, 1); dg <- round(rnorm(n), 4); u <- round(rnorm(m) * 0.5, 4); w <- round(rnorm(n) * 0.5, 4)
  Bm <- function(x, args) { y <- numeric(m); y[1:n] <- dg * x; y + u * sum(w * x) }
  Bt <- function(y, args) { x <- dg * y[1:n]; x + w * sum(u * y) }
  o <- svds(Bm, k, Atrans = Bt, dim = c(m, n), opts = list(tol = 1e-14, maxitr = 5000))
  cases[[length(cases) + 1]] <- case("os", c(m, n, k, dg, u, w), sum(o$d * seq_along(o$d)), rel = 1e-6, abs = 1e-8)
}
emit("spectra_opsvd", "RSpectra", list(cases))
