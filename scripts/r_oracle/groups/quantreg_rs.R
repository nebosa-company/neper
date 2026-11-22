# quantreg restricted fits and rqss with the total-variation penalty
#   rrq: args (0, n, p, tau, n2, j, y[n], X[n x p, column-major, intercept first], R[n2 x p, column-major], r[n2]), coefficient j of rq.fit.fnc
#   rqss: args (1, n, lambda, tau, dorder, j, y[n], x[n]), coefficient j (0-based) of rqss(y ~ qss(x, lambda, Dorder = dorder), tau)
suppressMessages(library(quantreg))
cases <- list()
set.seed(20261123)
for (rep in 1:6) {
  n <- sample(40:70, 1); p <- sample(2:4, 1)
  X <- cbind(1, matrix(round(rnorm(n * (p - 1)), 3), n, p - 1))
  y <- round(X %*% c(1, seq_len(p - 1)) + rt(n, 3), 3)
  n2 <- sample(1:3, 1)
  R <- matrix(round(rnorm(n2 * p), 2), n2, p)
  ols <- coef(lm.fit(X, y))
  r <- round(c(R %*% ols) + 0.3, 3)
  for (tau in c(0.25, 0.5, 0.75)) {
    z <- try(rq.fit.fnc(X, y, R, r, tau = tau), silent = TRUE)
    if (inherits(z, "try-error")) next
    b <- z$coefficients
    for (j in seq_len(p)) cases[[length(cases) + 1]] <- case("rq", c(0, n, p, tau, n2, j - 1, y, X, R, r), b[j], rel = 1e-9, abs = 1e-9)
  }
}
for (rep in 1:4) {
  n <- sample(22:32, 1)
  x <- if (rep %% 2 == 0) round(runif(n, 0, 10), 1) else round(runif(n, 0, 10), 3)
  y <- round(sin(x) + rnorm(n, sd = 0.4), 3)
  for (dorder in c(1, 0)) for (tau in c(0.5, 0.25)) {
    lambda <- if (dorder == 1) 0.5 else 0.3
    f <- suppressWarnings(rqss(y ~ qss(x, lambda = lambda, Dorder = dorder), tau = tau, data = data.frame(x = x, y = y)))
    b <- coef(f)
    for (j in seq_along(b)) cases[[length(cases) + 1]] <- case("rq", c(1, n, lambda, tau, dorder, j - 1, y, x), b[j], rel = 1e-8, abs = 1e-8)
  }
}
emit("quantreg_rs", "quantreg", list(cases))
