# mixsqp: the mixture proportions and the objective value on likelihood matrices.
#   args: (n, m, L[n*m] column-major, w[n], q)  q 0..m-1 x, m value
suppressMessages(library(mixsqp))
cases <- list()
set.seed(20261116)
for (rep in 1:20) {
  n <- sample(30:150, 1); m <- sample(3:10, 1); s <- c(0.5, 1, 2)[rep %% 3 + 1]
  L <- round(exp(matrix(rnorm(n * m) * s, n, m)), 6); w <- if (rep %% 2 == 0) round(runif(n, 0.2, 3), 3) else rep(1, n)
  r <- mixsqp(L, w, control = list(verbose = FALSE, convtol.sqp = 1e-12, convtol.activeset = 1e-12, maxiter.sqp = 1000))
  out <- c(r$x, r$value)
  for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("mix", c(n, m, L, w, q - 1), out[q], rel = 1e-5, abs = 1e-5)
}
# the SQP itself ("sqp", tol.svd = 0 so the full matrix is used): q 0..m-1 x, m value, m+1 status (0 converged), m+2 progress rows, m+3 sum of nqp, m+4 sum of nls, m+5 nonzeros at the end
for (rep in 1:30) {
  n <- sample(30:150, 1); m <- sample(3:12, 1); s <- c(0.5, 1, 2, 3)[rep %% 4 + 1]
  L <- round(exp(matrix(rnorm(n * m) * s, n, m)), 6); w <- if (rep %% 2 == 0) round(runif(n, 0.2, 3), 3) else rep(1, n)
  r <- suppressWarnings(mixsqp(L, w, control = list(verbose = FALSE, tol.svd = 0)))
  p <- r$progress
  out <- c(r$x, r$value, if (r$status == "converged to optimal solution") 0 else 1, nrow(p), sum(p$nqp, na.rm = TRUE), sum(p$nls, na.rm = TRUE), p$nnz[nrow(p)])
  for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("sqp", c(n, m, L, w, q - 1), out[q], rel = if (q <= m + 1) 1e-6 else 0, abs = if (q <= m + 1) 1e-8 else 0)
}
emit("mixsqp", "mixsqp", list(cases))
