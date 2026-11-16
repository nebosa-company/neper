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
emit("mixsqp", "mixsqp", list(cases))
