# gbmpkg: the narrow port e.algo.stat.gbmpkg against R gbm, no subsampling (bag.fraction = 1, train.fraction = 1) for the gaussian,
# bernoulli, poisson, adaboost and laplace losses. The data is a formula over the row index, so the
# fixture builds the same numbers without a generator: 40 rows of 3 variables, distinct within a column.
# A case is (loss, ntrees, shrinkage, depth, minobs, k, row) with k 0 for the fit at a training row
# (fn "gbm_fit"), 1..3 for the relative influence of variable k (row 0, fn "gbm_inf"), and k = 10 + trees
# for predict at new row `row` (1..5) using the first `trees` trees (fn "gbm_pred").
library(gbm)

N <- 40
P <- 3
col <- function(i, j) ((i * 37 + j * 101 + i * j * 13) %% 997) / 997 + i * 1e-6
make_x <- function(shift = 0) {
  i <- seq_len(N) + shift
  data.frame(x1 = col(i, 1), x2 = col(i, 2), x3 = col(i, 3))
}
make_y <- function(loss, x) {
  i <- seq_len(nrow(x))
  e <- ((i * 53) %% 101) / 101
  switch(as.character(loss),
    "0" = 3 * x$x1 + (x$x2 > 0.5) * 2 + e,
    "1" = as.numeric(x$x1 + 0.4 * e > 0.55),
    "2" = floor(5 * x$x1 + 2 * e),
    "3" = as.numeric(x$x2 + 0.4 * e > 0.55),
    "4" = 3 * x$x1 - (x$x3 > 0.4) * 2 + e)
}
dist <- c("gaussian", "bernoulli", "poisson", "adaboost", "laplace")
settings <- list(c(20, 0.1, 1, 2), c(30, 0.05, 2, 3), c(15, 0.2, 3, 1))

cases <- list()
for (loss in 0:4) for (s in settings) {
  x <- make_x(0)
  y <- make_y(loss, x)
  m <- gbm.fit(x, y, distribution = dist[loss + 1], n.trees = s[1], interaction.depth = s[3], n.minobsinnode = s[4],
               shrinkage = s[2], bag.fraction = 1, nTrain = N, keep.data = FALSE, verbose = FALSE)
  head <- c(loss, s[1], s[2], s[3], s[4])
  tol <- 1e-9
  for (r in seq_len(N)) cases[[length(cases) + 1]] <- case("gbm_fit", c(head, 0, r), m$fit[r], rel = tol, abs = 1e-10)
  rel <- summary(m, plotit = FALSE, order = FALSE)$rel.inf
  for (k in 1:P) cases[[length(cases) + 1]] <- case("gbm_inf", c(head, k, 0), rel[k], rel = tol, abs = 1e-9)
  nx <- make_x(1000)[1:5, ]
  for (use in c(s[1], s[1] %/% 2)) {
    p <- predict(m, nx, n.trees = use, type = "link")
    for (r in 1:5) cases[[length(cases) + 1]] <- case("gbm_pred", c(head, 10 + use, r), p[r], rel = tol, abs = 1e-10)
  }
}
emit("gbmpkg", "gbm", list(cases))
