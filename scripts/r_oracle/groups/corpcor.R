# corpcor (unweighted): shrinkage lambdas, var.shrink, cor.shrink, cov.shrink, pseudoinverse.
#   args: (n, p, lam, lamv, x row-wise..., stat)   fn "lambda_cor" "lambda_var" (no stat), "var" "cor" "cov" "pinv": stat 0 length 1 sum 2 position-weighted sum 3 first 4 last 5 sum of squares
#   lam / lamv < 0 mean estimated;  pinv: (n, p, 0, 0, x ...) is the n x p matrix, the answer p x n row-major
suppressMessages(library(corpcor))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-10)
set.seed(20261115)
vec <- function(fn, a, v) {
  v <- as.numeric(v); w <- seq_along(v)
  st <- c(length(v), sum(v), sum(w * v), v[1], v[length(v)], sum(v^2))
  for (j in 0:5) add(fn, c(a, j), st[j + 1])
}
rowvec <- function(m) as.vector(t(m))
for (rep in 1:10) {
  n <- c(15, 20, 30, 12, 40, 25, 10, 18, 50, 9)[rep]; p <- c(3, 5, 8, 6, 4, 12, 15, 2, 10, 20)[rep]
  m <- matrix(rnorm(n * p), n, p) %*% matrix(runif(p * p, -1, 1), p, p) + matrix(rnorm(p, 0, 2), n, p, byrow = TRUE)
  m <- round(m, 4)
  a0 <- c(n, p, -1, -1, rowvec(m))
  add("lambda_cor", a0, estimate.lambda(m, verbose = FALSE)); add("lambda_var", a0, estimate.lambda.var(m, verbose = FALSE))
  vec("var", a0, var.shrink(m, verbose = FALSE)); vec("cor", a0, cor.shrink(m, verbose = FALSE)); vec("cov", a0, cov.shrink(m, verbose = FALSE))
  for (lam in c(0, 0.3, 1)) { a1 <- c(n, p, lam, 0.2, rowvec(m)); vec("cor", a1, cor.shrink(m, lambda = lam, verbose = FALSE)); vec("cov", a1, cov.shrink(m, lambda = lam, lambda.var = 0.2, verbose = FALSE)); vec("var", a1, var.shrink(m, lambda.var = 0.2, verbose = FALSE)) }
  vec("pcor", a0, rowvec(pcor.shrink(m, verbose = FALSE)))
  vec("pcor", c(n, p, 0.3, 0, rowvec(m)), rowvec(pcor.shrink(m, lambda = 0.3, verbose = FALSE)))
  vec("pinv", c(n, p, 0, 0, rowvec(m)), rowvec(pseudoinverse(m)))
}
low <- round(matrix(rnorm(8 * 2), 8, 2) %*% matrix(rnorm(2 * 5), 2, 5), 4)
vec("pinv", c(8, 5, 0, 0, rowvec(low)), rowvec(pseudoinverse(low)))
emit("corpcor", "corpcor", list(cases))
