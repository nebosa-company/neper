# irlba::svdr on a sparse Matrix (dgCMatrix) under set.seed: the singular values after the same number of passes as dense input (tol 1e-5, so R's iterate, not the exact values).
# Args: (m, n, k, extra, seed, j, nnz, i[nnz] 0-based, j[nnz] 0-based, x[nnz]): the j-th singular value.
suppressMessages({library(irlba); library(Matrix)})
cases <- list()
set.seed(20262771)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("srsp", args, want, rel = 1e-9, abs = 1e-11)
for (rep in 1:16) {
  m <- sample(30:50, 1); n <- sample(12:20, 1); if (rep %% 4 == 0) { t <- m; m <- n; n <- t }
  k <- sample(2:4, 1); ex <- sample(3:8, 1); sd <- sample(1:100000, 1)
  A <- rsparsematrix(m, n, density = 0.3, rand.x = function(q) round(rnorm(q), 4))
  set.seed(sd); r <- svdr(A, k, extra = ex)
  s <- summary(A)
  for (j in 1:k) add(c(m, n, k, ex, sd, j - 1, nrow(s), s$i - 1, s$j - 1, s$x), r$d[j])
}
emit("spectra_svdrsp", c("irlba", "Matrix"), list(cases))
