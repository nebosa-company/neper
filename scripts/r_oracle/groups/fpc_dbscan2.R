# fpc::dbscan beyond the default: method "raw" and "dist", scale = TRUE, seeds, showplot = FALSE with countmode, dbscanCBI-style noise relabelling and predict.dbscan.
#   "dm": (n, p, eps, minpts, method, scale, what, x row-major); method 0 hybrid 1 raw 2 dist; what 0 sum(i * label[i]), 1 sum(i * isseed[i]), 2 the number of clusters
#   "dp": (n, p, eps, minpts, m, x row-major, newdata m by p row-major); the answer is sum(i * predict.dbscan(...)[i])
suppressMessages(library(fpc))
cases <- list()
set.seed(20269981)
for (rep in 1:18) {
  p <- sample(2:3, 1); k <- sample(2:4, 1); m <- sample(18:30, k, replace = TRUE)
  ctr <- matrix(runif(k * p, 0, 8), k, p)
  x <- do.call(rbind, lapply(seq_len(k), function(g) matrix(rnorm(m[g] * p, 0, 0.6), m[g], p) + rep(ctr[g, ], each = m[g])))
  x <- round(rbind(x, matrix(runif(8 * p, -1, 9), 8, p)), 4); n <- nrow(x)
  sc <- rep %% 3 == 0
  eps <- (if (sc) c(0.25, 0.35, 0.45) else c(0.5, 0.7, 0.9))[rep %% 3 + 1]; mp <- c(3, 4, 5)[rep %% 3 + 1]; meth <- rep %% 3
  r <- switch(meth + 1, dbscan(x, eps, mp, scale = sc, method = "hybrid", showplot = FALSE, countmode = NULL),
              dbscan(x, eps, mp, scale = sc, method = "raw"),
              dbscan(dist(if (sc) scale(x) else x), eps, mp, method = "dist"))
  fl <- as.vector(t(x))
  for (w in 0:2) cases[[length(cases) + 1]] <- case("dm", c(n, p, eps, mp, meth, as.numeric(sc), w, fl), c(sum(seq_len(n) * r$cluster), sum(seq_len(n) * r$isseed), max(r$cluster))[w + 1], rel = 0, abs = 0)
  if (rep %% 2 == 0 && !is.null(dbscan(x, eps, mp)$isseed)) {
    mm <- sample(5:25, 1); nw <- matrix(runif(mm * p, -1, 9), mm, p); nw <- round(nw, 4)
    r0 <- dbscan(x, eps, mp)
    pr <- predict(r0, x, nw)
    cases[[length(cases) + 1]] <- case("dp", c(n, p, eps, mp, mm, fl, as.vector(t(nw))), sum(seq_len(mm) * pr), rel = 0, abs = 0)
  }
}
emit("fpc_dbscan2", "fpc", list(cases))
