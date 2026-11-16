# Matrix: expm (sum, position-weighted sum and trace of the result), norms 1 / I / F / M.
#   args: (n, A row-major[n*n])
suppressMessages(library(Matrix))
cases <- list()
add <- function(fn, args, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-9)
set.seed(20261116)
for (rep in 1:30) {
  n <- sample(1:7, 1); sc <- c(0.05, 0.5, 1, 3, 8)[(rep %% 5) + 1]
  A <- matrix(round(rnorm(n * n) * sc, 3), n, n); a <- c(n, as.vector(t(A)))
  E <- as.matrix(expm(Matrix(A))); v <- as.vector(t(E))
  add("expm_sum", a, sum(v)); add("expm_w", a, sum(seq_along(v) * v)); add("expm_tr", a, sum(diag(E)))
  add("norm1", a, norm(A, "1")); add("normI", a, norm(A, "I")); add("normF", a, norm(A, "F")); add("normM", a, norm(A, "M"))
}
emit("matrix", "Matrix", list(cases))
