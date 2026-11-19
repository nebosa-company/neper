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
  sw <- summary(fw)$standard.errors; if (is.null(dim(sw))) sw <- matrix(sw, 1)
  cases[[length(cases) + 1]] <- case("se", aw, sum(as.vector(t(sw)) * seq_along(sw)), rel = 1e-5, abs = 1e-8)
}
# nnet(), one hidden layer: "netv" the value, "nets" the sum of the fitted values, "netw" the position-weighted sum of the final weights; args (n, p, h, k, mode, decay, maxit, skip, wts0[nw], x[n p] row-major,
# y[n k] row-major, case weights[n]); mode 0 linout (SSE), 1 logistic outputs (SSE), 2 logistic outputs with entropy = TRUE, 3 softmax; the output unit's weights are bias, hidden units, (skip) inputs
for (rep in 1:48) {
  n <- sample(40:100, 1); p <- sample(1:3, 1); h <- sample(1:4, 1); dc <- c(0, 0.01, 0.1)[rep %% 3 + 1]; sk <- rep %% 2 == 0; mode <- (rep - 1) %% 4
  k <- if (mode == 0) sample(1:2, 1) else if (mode == 3) sample(2:3, 1) else sample(1:3, 1)
  x <- matrix(rnorm(n * p), n)
  y <- switch(mode + 1,
    matrix(sin(x[, 1]) + 0.5 * rowSums(x) + rnorm(n * k, 0, 0.2), n, k),
    matrix(1 / (1 + exp(-(x[, 1] + rnorm(n * k, 0, 0.5)))), n, k),
    matrix(rbinom(n * k, 1, 1 / (1 + exp(-(x[, 1])))), n, k),
    class.ind(sample(k, n, TRUE, prob = seq_len(k))))
  wv <- rep(1, n)
  nw <- h * (p + 1) + k * (1 + h + (if (sk) p else 0)); set.seed(rep * 17); w0 <- runif(nw, -0.7, 0.7)
  f <- tryCatch(suppressWarnings(nnet(x, y, size = h, linout = (mode == 0), entropy = (mode == 2), softmax = (mode == 3), skip = sk, decay = dc, Wts = w0, maxit = 100, trace = FALSE)), error = function(e) NULL)
  if (is.null(f) || f$convergence != 0) next  # a run that hits the iteration cap amplifies rounding differences between the two programs
  a <- c(n, p, h, k, mode, dc, 100, as.numeric(sk), w0, as.vector(t(x)), as.vector(t(y)), wv)
  cases[[length(cases) + 1]] <- case("netv", a, f$value, rel = 1e-7, abs = 1e-9)
  cases[[length(cases) + 1]] <- case("nets", a, sum(f$fitted.values), rel = 1e-7, abs = 1e-9)
  cases[[length(cases) + 1]] <- case("netw", a, sum(f$wts * seq_along(f$wts)), rel = 1e-6, abs = 1e-9)
}
# the same from set.seed: "sdv", "sds", "sdw" args (n, p, h, k, mode, decay, maxit, skip, seed, rang, x, y, case weights): the start weights are runif(nwts, -rang, rang) drawn by nnet itself
for (rep in 1:40) {
  n <- sample(40:100, 1); p <- sample(1:3, 1); h <- sample(1:4, 1); dc <- c(0, 0.01, 0.1)[rep %% 3 + 1]; sk <- rep %% 2 == 0; mode <- (rep - 1) %% 4; rg <- c(0.7, 0.5, 1)[rep %% 3 + 1]
  k <- if (mode == 0) sample(1:2, 1) else if (mode == 3) sample(2:3, 1) else sample(1:3, 1)
  x <- matrix(rnorm(n * p), n)
  y <- switch(mode + 1,
    matrix(sin(x[, 1]) + 0.5 * rowSums(x) + rnorm(n * k, 0, 0.2), n, k),
    matrix(1 / (1 + exp(-(x[, 1] + rnorm(n * k, 0, 0.5)))), n, k),
    matrix(rbinom(n * k, 1, 1 / (1 + exp(-(x[, 1])))), n, k),
    class.ind(sample(k, n, TRUE, prob = seq_len(k))))
  sd <- sample(1:100000, 1); set.seed(sd)
  f <- tryCatch(suppressWarnings(nnet(x, y, size = h, linout = (mode == 0), entropy = (mode == 2), softmax = (mode == 3), skip = sk, rang = rg, decay = dc, maxit = 100, trace = FALSE)), error = function(e) NULL)
  if (is.null(f) || f$convergence != 0) next
  a <- c(n, p, h, k, mode, dc, 100, as.numeric(sk), sd, rg, as.vector(t(x)), as.vector(t(y)), rep(1, n))
  cases[[length(cases) + 1]] <- case("sdv", a, f$value, rel = 1e-7, abs = 1e-9)
  cases[[length(cases) + 1]] <- case("sds", a, sum(f$fitted.values), rel = 1e-7, abs = 1e-9)
  cases[[length(cases) + 1]] <- case("sdw", a, sum(f$wts * seq_along(f$wts)), rel = 1e-6, abs = 1e-9)
}
emit("nnet", "nnet", list(cases))
