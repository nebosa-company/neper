# performancepkg: performance indices of an lm. The mae is mean(abs(resid)), which performance_mae returns when run on its own but which came back NaN inside generate.R.
#   args: (which 0 r2, 1 r2_adjusted, 2 rmse, 3 mae, 4 mse, 5 sigma, 6 loglik, 7 aic, 8 aicc, 9 bic; n; p; y (n); x row-major n by p with the intercept column)
suppressMessages(library(performance))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-11)
set.seed(20262012)
for (rep in 1:25) {
  n <- sample(20:120, 1); p <- sample(2:5, 1); X <- cbind(1, matrix(round(rnorm(n * (p - 1)), 4), n, p - 1)); y <- round(as.vector(X %*% runif(p, -1, 1)) + rnorm(n), 4)
  m <- lm(y ~ X[, -1, drop = FALSE])
  v <- c(r2(m)$R2, r2(m)$R2_adjusted, performance_rmse(m), mean(abs(resid(m))), performance_mse(m), sigma(m), as.numeric(logLik(m)), performance_aic(m), performance_aicc(m), BIC(m))
  for (w in 0:9) add("lm", c(w, n, p, y, as.vector(t(X))), as.numeric(v[w + 1]))
}
emit("performancepkg", "performance", list(cases))
