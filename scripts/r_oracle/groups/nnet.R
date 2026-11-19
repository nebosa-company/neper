# nnet::multinom (no decay), fitted tightly (reltol 1e-14) so the likelihood optimum is what is compared.
#   args: (n, p, K, decay, y[n] 0-based class, x[n*p] row-major with the constant first, case weights[n])
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
  a <- c(n, p, K, 0, y, as.vector(t(x)), rep(1, n))
  add("dev", a, deviance(f)); add("coef", a, sum(as.vector(t(cf)) * seq_along(cf)))
  dc <- c(0.01, 0.1, 1)[rep %% 3 + 1]
  fd <- multinom(y ~ ., data = d, decay = dc, trace = FALSE, maxit = 5000, reltol = 1e-14, abstol = 1e-14)
  cd <- coef(fd); if (is.null(dim(cd))) cd <- matrix(cd, 1)
  ad <- c(n, p, K, dc, y, as.vector(t(x)), rep(1, n))
  add("dev", ad, deviance(fd)); add("coef", ad, sum(as.vector(t(cd)) * seq_along(cd)))
  wv <- sample(1:4, n, TRUE)
  fw <- multinom(y ~ ., data = d, weights = wv, decay = dc, trace = FALSE, maxit = 5000, reltol = 1e-14, abstol = 1e-14)
  cw <- coef(fw); if (is.null(dim(cw))) cw <- matrix(cw, 1)
  aw <- c(n, p, K, dc, y, as.vector(t(x)), wv)
  add("dev", aw, deviance(fw)); add("coef", aw, sum(as.vector(t(cw)) * seq_along(cw)))
}
emit("nnet", "nnet", list(cases))
