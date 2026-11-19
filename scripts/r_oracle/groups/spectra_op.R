# RSpectra: eigs_sym with a function operator A(x) = D x + u (u' x) + w (w' x) (diagonal plus two rank-one terms, symmetric). Args: (n, k, which 0 LM 1 LA 2 SA, d[n], u[n], w[n]): sum of value * position.
suppressMessages(library(RSpectra))
cases <- list()
set.seed(20262354)
for (rep in 1:20) {
  n <- sample(12:30, 1); k <- sample(2:4, 1); wh <- (rep - 1) %% 3; d <- round(rnorm(n), 4); u <- round(rnorm(n) * 0.3, 4); w <- round(rnorm(n) * 0.3, 4)
  f <- function(x, args) d * x + u * sum(u * x) + w * sum(w * x)
  o <- eigs_sym(f, k, n = n, which = c("LM", "LA", "SA")[wh + 1], opts = list(tol = 1e-14, maxitr = 5000))
  cases[[length(cases) + 1]] <- case("op", c(n, k, wh, d, u, w), sum(o$values * seq_along(o$values)), rel = 1e-6, abs = 1e-8)
}
emit("spectra_op", "RSpectra", list(cases))
