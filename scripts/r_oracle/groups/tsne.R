# Rtsne with theta = 0 and a given Y_init: "ts" args (n, d, dims, perplexity, max_iter, stop_lying_iter, mom_switch_iter, momentum, final_momentum, eta, exaggeration, x[n*d] row-major,
# y0[n*dims] row-major, index of the output coordinate, normalize), the coordinate (row-major) of the embedding
suppressMessages(library(Rtsne))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("ts", args, want, rel = 1e-6, abs = 1e-8)
set.seed(20262100)
for (rep in 1:10) {
  n <- sample(15:40, 1); d <- sample(2:6, 1); dims <- sample(2:3, 1); perp <- sample(3:min(8, floor((n - 1) / 3)), 1)
  X <- matrix(round(rnorm(n * d) * 3, 3), n, d); Y0 <- matrix(round(rnorm(n * dims) * 1e-2, 6), n, dims)
  mi <- sample(c(40, 100), 1); norm <- rep %% 2 == 0
  sl <- if (rep %% 3 == 0) 12 else 0; ms <- if (rep %% 3 == 0) 8 else 0; if (sl > 0) mi <- 20
  r <- Rtsne(X, dims = dims, perplexity = perp, theta = 0, pca = FALSE, normalize = norm, max_iter = mi, Y_init = Y0, stop_lying_iter = sl, mom_switch_iter = ms, check_duplicates = FALSE)
  for (j in seq_len(n * dims)) add(c(n, d, dims, perp, mi, sl, ms, 0.5, 0.8, 200, 12, as.vector(t(X)), as.vector(t(Y0)), j - 1, as.numeric(norm)), as.vector(t(r$Y))[j])
}
emit("tsne", "Rtsne", list(cases))
