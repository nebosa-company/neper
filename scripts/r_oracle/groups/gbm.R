# gbm, gaussian loss, no subsampling: the fit at training row i after n.trees trees.
#   args: (n, p, ntrees, shrinkage, depth, minobs, i, 0, y[n], X[n p] column-major)
suppressMessages(library(gbm))
cases <- list()
set.seed(20261201)
for (rep in 1:12) {
  n <- sample(60:150, 1); p <- sample(2:5, 1); X <- matrix(round(rnorm(n * p), 3), n, p); y <- round(sin(2 * X[, 1]) + X[, 2]^2 * 0.5 + rnorm(n, 0, 0.3), 3)
  d <- sample(1:3, 1); sh <- c(0.1, 0.05, 0.3)[rep %% 3 + 1]; nt <- c(10, 40)[rep %% 2 + 1]; mo <- c(10, 5)[rep %% 2 + 1]
  df <- data.frame(y = y, X); names(df) <- c("y", paste0("V", 1:p))
  f <- gbm(y ~ ., data = df, distribution = "gaussian", n.trees = nt, shrinkage = sh, interaction.depth = d, n.minobsinnode = mo, bag.fraction = 1, train.fraction = 1, keep.data = TRUE, verbose = FALSE)
  pr <- predict(f, df, n.trees = nt)
  for (i in c(1, 7, 20, n)) cases[[length(cases) + 1]] <- case("fit", c(n, p, nt, sh, d, mo, i - 1, 0, y, X), pr[i], rel = 1e-8, abs = 1e-10)
}
emit("gbm", "gbm", list(cases))
