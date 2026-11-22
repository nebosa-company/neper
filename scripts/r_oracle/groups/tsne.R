# Rtsne with theta = 0 and a given Y_init: "ts" args (n, d, dims, perplexity, max_iter, stop_lying_iter, mom_switch_iter, momentum, final_momentum, eta, exaggeration, x[n*d] row-major,
# y0[n*dims] row-major, index of the output coordinate, normalize), the coordinate (row-major) of the embedding
suppressMessages(library(Rtsne))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("ts", args, want, rel = 1e-7, abs = 1e-9)
set.seed(20262100)
for (rep in 1:10) {
  n <- sample(15:40, 1); d <- sample(2:6, 1); dims <- sample(2:3, 1); perp <- sample(3:min(8, floor((n - 1) / 3)), 1)
  X <- matrix(round(rnorm(n * d) * 3, 3), n, d); Y0 <- matrix(round(rnorm(n * dims) * 1e-2, 6), n, dims)
  mi <- sample(c(40, 100), 1); norm <- rep %% 2 == 0
  sl <- if (rep %% 3 == 0) 12 else 0; ms <- if (rep %% 3 == 0) 8 else 0; if (sl > 0) mi <- 20
  r <- Rtsne(X, dims = dims, perplexity = perp, theta = 0, pca = FALSE, normalize = norm, max_iter = mi, Y_init = Y0, stop_lying_iter = sl, mom_switch_iter = ms, check_duplicates = FALSE)
  for (j in seq_len(n * dims)) add(c(n, d, dims, perp, mi, sl, ms, 0.5, 0.8, 200, 12, as.vector(t(X)), as.vector(t(Y0)), j - 1, as.numeric(norm)), as.vector(t(r$Y))[j])
}
# is_distance = TRUE: the same call with x the n by n distance matrix (d = n), mode 2
for (rep in 1:4) {
  n <- sample(15:30, 1); dims <- 2; perp <- sample(3:min(8, floor((n - 1) / 3)), 1)
  X <- matrix(round(rnorm(n * 3) * 3, 3), n, 3); Dm <- as.matrix(dist(X)); Y0 <- matrix(round(rnorm(n * dims) * 1e-2, 6), n, dims)
  r <- Rtsne(Dm, is_distance = TRUE, dims = dims, perplexity = perp, theta = 0, max_iter = 40, Y_init = Y0, check_duplicates = FALSE)
  for (j in seq_len(n * dims)) add(c(n, n, dims, perp, 40, 0, 0, 0.5, 0.8, 200, 12, as.vector(t(Dm)), as.vector(t(Y0)), j - 1, 2), as.vector(t(r$Y))[j])
}
# pca = TRUE with initial_dims = k < d (normalize on): "ts" with the mode 3 and k carried in the column count slot after the coordinates (the input has d columns, the t-SNE runs on k)
for (rep in 1:5) {
  n <- sample(15:30, 1); d <- sample(4:7, 1); k <- sample(2:3, 1); dims <- 2; perp <- sample(3:min(8, floor((n - 1) / 3)), 1)
  X <- matrix(round(rnorm(n * d) * 3, 3), n, d) %*% diag(seq(d, 1)); X <- round(X, 3); Y0 <- matrix(round(rnorm(n * dims) * 1e-2, 6), n, dims)
  r <- Rtsne(X, dims = dims, perplexity = perp, theta = 0, pca = TRUE, initial_dims = k, max_iter = 40, Y_init = Y0, check_duplicates = FALSE)
  for (j in seq_len(n * dims)) add(c(n, d, dims, perp, 40, 0, 0, 0.5, 0.8, 200, 12, as.vector(t(X)), as.vector(t(Y0)), j - 1, 3, k), as.vector(t(r$Y))[j])
}
# the random start (Y_init = NULL, so stop_lying_iter = mom_switch_iter = 250) under set.seed: "tr" args (seed, n, d, dims, perplexity, max_iter, normalize, x[n*d], index)
for (rep in 1:8) {
  n <- sample(15:35, 1); d <- sample(2:5, 1); dims <- 2; perp <- sample(3:min(8, floor((n - 1) / 3)), 1); mi <- c(5, 10)[1 + rep %% 2]
  X <- matrix(round(rnorm(n * d) * 3, 3), n, d); sd0 <- sample(1:100000, 1); norm <- rep %% 2 == 0
  set.seed(sd0); r <- Rtsne(X, dims = dims, perplexity = perp, theta = 0, pca = FALSE, normalize = norm, max_iter = mi, check_duplicates = FALSE)
  for (j in seq_len(n * dims)) cases[[length(cases) + 1]] <- case("tr", c(sd0, n, d, dims, perp, mi, as.numeric(norm), as.vector(t(X)), j - 1), as.vector(t(r$Y))[j], rel = 1e-7, abs = 1e-9)
}
emit("tsne", "Rtsne", list(cases))
