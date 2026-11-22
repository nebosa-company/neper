# uwot::umap_transform with a precomputed neighbour graph (nn_method = list(idx, dist)) on a model trained from a precomputed graph. "ut": args (seed, nq, k, nt, nd, n_epochs, alpha, a, b, gamma,
# negative_sample_rate, local_connectivity, weighted, idx[nq*k] 0-based row-major, dist[nq*k], train[nt*nd] row-major, sel); sel >= 0 one coordinate of the new embedding, -1 the sum of squares,
# -2 the sum of coordinate * (1-based position). The model's n_epochs is 30 or 45 and the transform runs the default max(2, round(n_epochs / 3)) unless n_epochs is given.
suppressMessages(library(uwot)); suppressMessages(library(FNN))
cases <- list()
sels <- function(nn) c(0, floor(nn / 2), nn - 1, -1, -2)
pick <- function(v, s) if (s >= 0) v[s + 1] else if (s == -1) sum(v^2) else sum(v * seq_along(v))
set.seed(20262301)
for (rep in 1:10) {
  nt <- sample(35:55, 1); d <- sample(3:5, 1); nd <- c(2, 2, 3)[1 + rep %% 3]; k <- sample(6:12, 1); nq <- sample(5:15, 1)
  X <- matrix(rnorm(nt * d), nt, d); Xn <- matrix(rnorm(nq * d) * 0.8, nq, d)
  kk <- get.knn(X, k - 1); idx <- cbind(1:nt, kk$nn.index); dist <- cbind(0, kk$nn.dist)
  md <- c(0.01, 0.1, 0.3)[1 + rep %% 3]; ab <- uwot:::find_ab_params(1, md)
  alpha <- c(1, 0.5, 1.5)[1 + rep %% 3]; gam <- c(1, 0.7)[1 + rep %% 2]; nsr <- c(5, 3, 7)[1 + rep %% 3]; lc <- c(1, 1, 1.5)[1 + rep %% 3]
  mne <- c(30, 45)[1 + rep %% 2]
  m <- umap(X, n_neighbors = k, n_components = nd, n_epochs = mne, learning_rate = alpha, a = ab[1], b = ab[2], repulsion_strength = gam, negative_sample_rate = nsr,
            local_connectivity = lc, init = "random", nn_method = list(idx = idx, dist = dist), ret_model = TRUE, seed = sample(1:1e5, 1), verbose = FALSE, n_threads = 1)
  q <- get.knnx(X, Xn, k)
  weighted <- rep %% 4 != 0; sd0 <- sample(1:100000, 1)
  ne <- if (rep %% 3 == 0) 12 else NULL
  tr <- umap_transform(NULL, m, nn_method = list(idx = q$nn.index, dist = q$nn.dist), n_epochs = ne, init = if (weighted) "weighted" else "average", seed = sd0, verbose = FALSE, n_threads = 1)
  nep <- if (is.null(ne)) max(2, round(mne / 3)) else ne
  v <- as.vector(t(tr))
  for (s in sels(length(v))) cases[[length(cases) + 1]] <- case("ut", c(sd0, nq, k, nt, nd, nep, alpha, ab[1], ab[2], gam, nsr, lc, as.numeric(weighted), as.vector(t(q$nn.index - 1)), as.vector(t(q$nn.dist)), as.vector(t(m$embedding)), s), pick(v, s), rel = 1e-9, abs = 1e-10)
}
emit("uwottr", "uwot", list(cases))
