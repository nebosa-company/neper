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
# nnet() regression (linout = TRUE), one hidden layer, no skip: "netv" the value, "nets" the sum of fitted values, "netw" the position-weighted sum of the final weights; args (n, p, h, decay, maxit, skip, wts0[nw], x[n p] row-major, y[n], case weights[n]); with skip the output also takes the p inputs (bias, hidden, inputs)
for (rep in 1:25) {
  n <- sample(40:120, 1); p <- sample(1:3, 1); h <- sample(1:4, 1); dc <- c(0, 0.01, 0.1)[rep %% 3 + 1]
  x <- matrix(rnorm(n * p), n); y <- sin(x[, 1]) + 0.5 * rowSums(x) + rnorm(n, 0, 0.2); wv <- rep(1, n)
  sk <- rep %% 2 == 0
  nw <- h * (p + 1) + h + 1 + (if (sk) p else 0); set.seed(rep * 17); w0 <- runif(nw, -0.7, 0.7)
  f <- nnet(x, y, size = h, linout = TRUE, skip = sk, decay = dc, Wts = w0, maxit = 100, trace = FALSE)
  if (f$convergence != 0) next  # a run that hits the iteration cap amplifies rounding differences between the two programs
  a <- c(n, p, h, dc, 100, as.numeric(sk), w0, as.vector(t(x)), y, wv)
  cases[[length(cases) + 1]] <- case("netv", a, f$value, rel = 1e-7, abs = 1e-9)
  cases[[length(cases) + 1]] <- case("nets", a, sum(f$fitted.values), rel = 1e-7, abs = 1e-9)
  cases[[length(cases) + 1]] <- case("netw", a, sum(f$wts * seq_along(f$wts)), rel = 1e-7, abs = 1e-9)
}
emit("nnet", "nnet", list(cases))
