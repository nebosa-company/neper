# rpart method "anova": numeric and factor predictors, missing values, case weights, costs, the control parameters, xval folds under set.seed, prune, predict.
# Layout of the cases: scripts/r_oracle/rpartfull_lib.R.
source(file.path(root, "scripts", "r_oracle", "rpartfull_lib.R"))
cases <- list()
set.seed(20266101)
for (rep in 1:34) {
  n <- sample(45:130, 1); p <- sample(2:5, 1)
  X <- data.frame(row.names = seq_len(n))
  for (j in seq_len(p)) {
    if (runif(1) < 0.35) X[[paste0("x", j)]] <- rp_fac(sample.int(L <- sample(2:6, 1), n, replace = TRUE), L)
    else X[[paste0("x", j)]] <- round(runif(n), 3)
  }
  num1 <- which(!vapply(X, is.factor, TRUE))[1]
  sig <- if (is.na(num1)) 0 else 3 * (X[[num1]] > 0.5)
  fx <- vapply(X, is.factor, TRUE)
  eff <- 0; for (j in which(fx)) eff <- eff + (as.integer(X[[j]]) %% 2) * 1.5
  y <- round(sig + eff + rnorm(n) * c(0.4, 1)[rep %% 2 + 1], 4)
  if (rep %% 4 == 0) for (j in sample(p, max(1, p - 1))) X[[j]][sample(n, round(n * 0.12))] <- NA
  for (r in which(rowSums(is.na(X)) == p)) X[r, 1] <- X[1, 1][!is.na(X[1, 1])][1]
  wt <- if (rep %% 5 == 0) round(runif(n, 0, 3), 2) else NULL
  cost <- if (rep %% 6 == 0) round(runif(p, 0.5, 3), 2) else NULL
  ctl <- list(minsplit = sample(c(6, 10, 20), 1), minbucket = sample(c(2, 4, 7), 1), cp = sample(c(0.003, 0.01, 0.03), 1),
              maxcompete = sample(0:4, 1), maxsurrogate = sample(0:5, 1), usesurrogate = sample(0:2, 1), surrogatestyle = sample(0:1, 1),
              maxdepth = sample(c(3, 5, 30), 1), xval = sample(c(0, 4, 7, 10), 1))
  nn <- 25; nd <- X[sample(n, nn, replace = TRUE), , drop = FALSE]
  for (j in seq_len(p)) if (!fx[j]) nd[[j]] <- round(nd[[j]] + rnorm(nn) * 0.02, 3)
  if (p > 1) nd[sample(nn, 5), sample(p, 1)] <- NA
  nd <- nd[rowSums(is.na(nd)) < p, , drop = FALSE]
  seed <- sample(1:100000, 1)
  cases <- c(cases, rp_cases(y, X, wt = wt, cost = cost, ctl = ctl, seed = seed, newX = nd, prunes = c(ctl$cp * 3)))
}
emit("rpartfull_a", "rpart", list(cases))
