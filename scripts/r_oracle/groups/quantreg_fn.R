# quantreg Frisch-Newton fits; args (n, p, tau, mode, seed, lambda, y..., X...) with X the n x (p-1) covariates (the intercept is added)
#   mode = 10 kind + j, coefficient j of: kind 0 rq method "fn"; 1 lasso with lambda scalar (c(0, rep(lambda, p - 1))); 2 lasso with the default
#   LassoLambdaHat after set.seed(seed); 3 method "pfn" after set.seed(seed); 4 the default lambda itself (j-th penalty)
suppressMessages(library(quantreg))
cases <- list()
set.seed(20261122)
for (rep in 1:8) {
  n <- sample(40:70, 1); p <- sample(2:4, 1)
  X <- matrix(round(rnorm(n * (p - 1)), 3), n, p - 1)
  y <- round(1 + X %*% seq_len(p - 1) + rt(n, 3), 3)
  seed <- sample(1000:9999, 1)
  for (tau in c(0.25, 0.5, 0.75)) {
    add <- function(kind, v, lambda = 0) for (j in seq_len(p)) cases[[length(cases) + 1]] <<- case("rq", c(n, p, tau, 10 * kind + j - 1, seed, lambda, y, X), v[j], rel = 1e-9, abs = 1e-9)
    add(0, coef(rq(y ~ X, tau = tau, method = "fn")))
    add(1, coef(rq(y ~ X, tau = tau, method = "lasso", lambda = 0.5)), 0.5)
    X1 <- cbind(1, X)
    set.seed(seed); add(2, coef(rq(y ~ X, tau = tau, method = "lasso")))
    set.seed(seed); add(4, LassoLambdaHat(X1, tau = tau))
    set.seed(seed); add(3, suppressWarnings(coef(rq(y ~ X, tau = tau, method = "pfn"))))
  }
}
emit("quantreg_fn", "quantreg", list(cases))
