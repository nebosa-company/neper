# Rtsne Barnes-Hut (theta > 0). "tb": given Y_init, args (n, d, dims, perplexity, max_iter, stop_lying_iter, mom_switch_iter, theta, mode, x[n*d] row-major, y0[n*dims], sel)
# "tr": random start under set.seed, args (seed, n, d, dims, perplexity, max_iter, theta, mode, x[n*d], sel). mode 0 plain, 1 normalize, 2 distance matrix, 3 pca to k (k after sel for "tb").
# sel >= 0 is one coordinate of the row-major embedding, -1 its sum of squares, -2 the sum of coordinate * (1-based position).
# Tolerance 1e-7 relative: gradient descent amplifies last-bit libm differences (exp, log) about tenfold per 20 iterations, so runs are kept to 40 iterations.
suppressMessages(library(Rtsne))
cases <- list()
sels <- function(Y, nn) c(0, floor(nn / 2), nn - 1, -1, -2)
pick <- function(v, s) if (s >= 0) v[s + 1] else if (s == -1) sum(v^2) else sum(v * seq_along(v))
emitcases <- function(fn, pre, v, post, rel = 1e-7, abs = 1e-9) {
  for (s in sels(v, length(v))) cases[[length(cases) + 1]] <<- case(fn, c(pre, s, post), pick(v, s), rel = rel, abs = abs)
}
set.seed(20262200)
for (rep in 1:14) {
  n <- sample(20:60, 1); d <- sample(2:6, 1); dims <- sample(c(2, 2, 3), 1)
  perp <- c(3, 4.5, 5, 6.5, 7)[1 + rep %% 5]; perp <- min(perp, floor((n - 2) / 3))
  X <- matrix(round(rnorm(n * d) * 3, 3), n, d); Y0 <- matrix(round(rnorm(n * dims) * 1e-2, 6), n, dims)
  theta <- c(0.2, 0.5, 0.8)[1 + rep %% 3]; norm <- rep %% 2 == 0
  mi <- sample(c(20, 30, 40), 1); sl <- if (rep %% 3 == 0) 15 else 0; ms <- if (rep %% 3 == 0) 10 else 0
  if (sl > 0) mi <- 30
  r <- Rtsne(X, dims = dims, perplexity = perp, theta = theta, pca = FALSE, normalize = norm, max_iter = mi, Y_init = Y0, stop_lying_iter = sl, mom_switch_iter = ms, check_duplicates = FALSE)
  emitcases("tb", c(n, d, dims, perp, mi, sl, ms, theta, as.numeric(norm), as.vector(t(X)), as.vector(t(Y0))), as.vector(t(r$Y)), NULL)
}
# distance matrix input
for (rep in 1:3) {
  n <- sample(20:40, 1); dims <- 2; perp <- sample(3:min(8, floor((n - 2) / 3)), 1)
  X <- matrix(round(rnorm(n * 3) * 3, 3), n, 3); Dm <- as.matrix(dist(X)); Y0 <- matrix(round(rnorm(n * dims) * 1e-2, 6), n, dims)
  r <- Rtsne(Dm, is_distance = TRUE, dims = dims, perplexity = perp, theta = 0.5, max_iter = 40, Y_init = Y0, check_duplicates = FALSE)
  emitcases("tb", c(n, n, dims, perp, 40, 0, 0, 0.5, 2, as.vector(t(Dm)), as.vector(t(Y0))), as.vector(t(r$Y)), NULL)
}
# pca = TRUE with initial_dims = k < d
for (rep in 1:3) {
  n <- sample(25:40, 1); d <- sample(4:7, 1); k <- sample(2:3, 1); dims <- 2; perp <- sample(3:min(8, floor((n - 2) / 3)), 1)
  X <- round(matrix(round(rnorm(n * d) * 3, 3), n, d) %*% diag(seq(d, 1)), 3); Y0 <- matrix(round(rnorm(n * dims) * 1e-2, 6), n, dims)
  r <- Rtsne(X, dims = dims, perplexity = perp, theta = 0.5, pca = TRUE, initial_dims = k, max_iter = 40, Y_init = Y0, check_duplicates = FALSE)
  emitcases("tb", c(n, d, dims, perp, 40, 0, 0, 0.5, 3, as.vector(t(X)), as.vector(t(Y0))), as.vector(t(r$Y)), k)
}
# random start (stop_lying_iter = mom_switch_iter = 250), so the vantage-point tree's draws precede the start
for (rep in 1:8) {
  n <- sample(20:50, 1); d <- sample(2:5, 1); dims <- c(2, 3)[1 + rep %% 2]; perp <- sample(3:min(8, floor((n - 2) / 3)), 1); mi <- c(10, 20)[1 + rep %% 2]
  X <- matrix(round(rnorm(n * d) * 3, 3), n, d); sd0 <- sample(1:100000, 1); theta <- c(0.3, 0.5)[1 + rep %% 2]; norm <- rep %% 2 == 0
  set.seed(sd0); r <- Rtsne(X, dims = dims, perplexity = perp, theta = theta, pca = FALSE, normalize = norm, max_iter = mi, check_duplicates = FALSE)
  emitcases("tr", c(sd0, n, d, dims, perp, mi, theta, as.numeric(norm), as.vector(t(X))), as.vector(t(r$Y)), NULL)
}
emit("tsnebh", "Rtsne", list(cases))
