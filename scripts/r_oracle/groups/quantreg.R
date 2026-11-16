# quantreg: rq coefficients (method br) for one tau.
#   args: (n, p, tau, j, y..., X...) with X the n x (p-1) covariates (the intercept is added), j the coefficient asked for
suppressMessages(library(quantreg))
cases <- list()
set.seed(20261116)
for (rep in 1:14) {
  n <- sample(15:60, 1); p <- sample(2:4, 1)
  X <- matrix(round(rnorm(n * (p - 1)), 3), n, p - 1)
  y <- round(1 + X %*% seq_len(p - 1) + rt(n, 3), 3)
  for (tau in c(0.1, 0.25, 0.5, 0.75, 0.9)) {
    f <- coef(rq(y ~ X, tau = tau, method = "br"))
    for (j in seq_len(p)) cases[[length(cases) + 1]] <- case("rq", c(n, p, tau, j - 1, y, X), f[j], rel = 1e-6, abs = 1e-8)
  }
}
emit("quantreg", "quantreg", list(cases))
