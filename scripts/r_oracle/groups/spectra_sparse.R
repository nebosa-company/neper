# RSpectra svds and eigs_sym on sparse Matrix inputs (triplets). Args: (kind 0 svds 1 eigs_sym LM, m, n, k, nnz, i[nnz] 0-based, j[nnz] 0-based, x[nnz]): the sum of value * position.
suppressMessages({library(RSpectra); library(Matrix)})
cases <- list()
set.seed(20262353)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("sps", args, want, rel = 1e-6, abs = 1e-8)
for (rep in 1:20) {
  m <- sample(30:60, 1); n <- sample(15:25, 1); k <- sample(2:4, 1); A <- rsparsematrix(m, n, density = 0.25, rand.x = function(nn) round(rnorm(nn), 4))
  s <- summary(A)
  o <- svds(A, k, opts = list(tol = 1e-14, maxitr = 5000)); add(c(0, m, n, k, nrow(s), s$i - 1, s$j - 1, s$x), sum(o$d * seq_along(o$d)))
  G <- as(crossprod(A) - Diagonal(n, 0.1), "generalMatrix"); g <- summary(G); e <- eigs_sym(G, k, which = "LM", opts = list(tol = 1e-14, maxitr = 5000))
  add(c(1, n, n, k, nrow(g), g$i - 1, g$j - 1, g$x), sum(e$values * seq_along(e$values)))
}
emit("spectra_sparse", c("RSpectra", "Matrix"), list(cases))
