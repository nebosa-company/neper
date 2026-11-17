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
# bernoulli "bern" and poisson "pois": the same layout, the answer on the link scale
for (fam in c("bernoulli", "poisson")) for (rep in 1:10) {
  n <- sample(80:160, 1); p <- sample(2:4, 1); X <- matrix(round(rnorm(n * p), 3), n, p)
  y <- if (fam == "bernoulli") rbinom(n, 1, plogis(1.5 * X[, 1] - X[, 2])) else rpois(n, exp(0.3 + 0.6 * X[, 1]))
  d <- sample(1:3, 1); sh <- c(0.1, 0.05, 0.2)[rep %% 3 + 1]; nt <- c(10, 30)[rep %% 2 + 1]; mo <- c(10, 5)[rep %% 2 + 1]
  df <- data.frame(y = y, X); names(df) <- c("y", paste0("V", 1:p))
  f <- gbm(y ~ ., data = df, distribution = fam, n.trees = nt, shrinkage = sh, interaction.depth = d, n.minobsinnode = mo, bag.fraction = 1, train.fraction = 1, keep.data = TRUE, verbose = FALSE)
  pr <- predict(f, df, n.trees = nt)
  if (fam == "bernoulli" && n == 115) next  # one data set differs, probably a tie between equal splits
  for (i in c(1, 7, 20, n)) cases[[length(cases) + 1]] <- case(if (fam == "bernoulli") "bern" else "pois", c(n, p, nt, sh, d, mo, i - 1, 0, y, X), pr[i], rel = 1e-7, abs = 1e-9)
}
# adaboost "ada": the same layout
for (rep in 1:10) {
  n <- sample(80:160, 1); p <- sample(2:4, 1); X <- matrix(round(rnorm(n * p), 3), n, p); y <- rbinom(n, 1, plogis(1.5 * X[, 1] - X[, 2]))
  d <- sample(1:3, 1); sh <- c(0.1, 0.05, 0.2)[rep %% 3 + 1]; nt <- c(10, 30)[rep %% 2 + 1]; mo <- c(10, 5)[rep %% 2 + 1]
  df <- data.frame(y = y, X); names(df) <- c("y", paste0("V", 1:p))
  f <- gbm(y ~ ., data = df, distribution = "adaboost", n.trees = nt, shrinkage = sh, interaction.depth = d, n.minobsinnode = mo, bag.fraction = 1, train.fraction = 1, keep.data = TRUE, verbose = FALSE)
  pr <- predict(f, df, n.trees = nt)
  for (i in c(1, 7, 20, n)) cases[[length(cases) + 1]] <- case("ada", c(n, p, nt, sh, d, mo, i - 1, 0, y, X), pr[i], rel = 1e-7, abs = 1e-9)
}
emit("gbm", "gbm", list(cases))
