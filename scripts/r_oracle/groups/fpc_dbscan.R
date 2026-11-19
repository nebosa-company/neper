# fpc::dbscan (default hybrid method): cluster labels (0 noise) and core-point flags. Args: (n, p, eps, minpts, what, idx, x row-major); what 0 label, 1 isseed.
suppressMessages(library(fpc))
cases <- list()
set.seed(20262101)
for (rep in 1:10) {
  p <- sample(2:3, 1); k <- sample(2:4, 1); m <- sample(20:35, k, replace = TRUE)
  ctr <- matrix(runif(k * p, 0, 8), k, p)
  x <- do.call(rbind, lapply(seq_len(k), function(g) matrix(rnorm(m[g] * p, 0, 0.6), m[g], p) + rep(ctr[g, ], each = m[g])))
  x <- rbind(x, matrix(runif(8 * p, -1, 9), 8, p))
  x <- round(x, 4); n <- nrow(x)
  eps <- c(0.5, 0.7, 0.9)[rep %% 3 + 1]; mp <- c(3, 4, 5)[rep %% 3 + 1]
  r <- dbscan(x, eps = eps, MinPts = mp)
  for (i in seq_len(n)) {
    cases[[length(cases) + 1]] <- case("db", c(n, p, eps, mp, 0, i - 1, as.vector(t(x))), r$cluster[i], rel = 0, abs = 0)
    cases[[length(cases) + 1]] <- case("db", c(n, p, eps, mp, 1, i - 1, as.vector(t(x))), as.numeric(r$isseed[i]), rel = 0, abs = 0)
  }
}
emit("fpc_dbscan", "fpc", list(cases))
