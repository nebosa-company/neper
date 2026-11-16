# nnet::multinom (no decay), fitted tightly (reltol 1e-14) so the likelihood optimum is what is compared.
#   args: (n, p, K, y[n] 0-based class, x[n*p] row-major with the constant first)
#   fn "dev" (deviance), "coef" (coefficient matrix of classes 2..K, row-major, weighted by position)
suppressMessages(library(nnet))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-5, abs = 1e-6)
set.seed(20261208)
for (rep in 1:20) {
  n <- sample(80:200, 1); p <- sample(2:4, 1); K <- sample(3:4, 1)
  x <- cbind(1, matrix(rnorm(n * (p - 1)), n))
  B <- matrix(rnorm(p * K, 0, 1), p); B[, 1] <- 0
  eta <- x %*% B; pr <- exp(eta) / rowSums(exp(eta))
  y <- apply(pr, 1, function(q) sample(0:(K - 1), 1, prob = q))
  if (length(unique(y)) < K) next
  d <- as.data.frame(x[, -1, drop = FALSE]); names(d) <- paste0("v", seq_len(p - 1)); d$y <- factor(y)
  f <- multinom(y ~ ., data = d, trace = FALSE, maxit = 5000, reltol = 1e-14, abstol = 1e-14)
  cf <- coef(f)
  if (is.null(dim(cf))) cf <- matrix(cf, 1)
  a <- c(n, p, K, y, as.vector(t(x)))
  add("dev", a, deviance(f)); add("coef", a, sum(as.vector(t(cf)) * seq_along(cf)))
}
emit("nnet", "nnet", list(cases))
