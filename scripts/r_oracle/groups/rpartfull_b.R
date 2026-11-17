# rpart method "class": gini and information splitting, priors, loss matrices, case weights, factor predictors (gray-code subset search), missing values, xval.
# Layout of the cases: scripts/r_oracle/rpartfull_lib.R.
source(file.path(root, "scripts", "r_oracle", "rpartfull_lib.R"))
cases <- list()
set.seed(20266102)
priors <- list(1, c(0.25, 0.75), c(0.125, 0.375, 0.5), c(0.125, 0.125, 0.25, 0.5))
for (rep in 1:36) {
  n <- sample(50:140, 1); p <- sample(2:5, 1); K <- sample(2:4, 1)
  X <- data.frame(row.names = seq_len(n))
  for (j in seq_len(p)) {
    if (runif(1) < 0.4) X[[paste0("x", j)]] <- rp_fac(sample.int(L <- sample(2:7, 1), n, replace = TRUE), L)
    else X[[paste0("x", j)]] <- round(runif(n), 3)
  }
  fx <- vapply(X, is.factor, TRUE)
  sc <- rnorm(n) * c(0.5, 1.2)[rep %% 2 + 1]
  for (j in seq_len(p)) sc <- sc + if (fx[j]) (as.integer(X[[j]]) %% 3) * 0.8 else 2 * X[[j]]
  cls <- as.integer(cut(sc, quantile(sc, seq(0, 1, length.out = K + 1)), include.lowest = TRUE))
  y <- factor(letters[cls], levels = letters[1:K])
  if (rep %% 4 == 0) for (j in sample(p, max(1, p - 1))) X[[j]][sample(n, round(n * 0.1))] <- NA
  for (r in which(rowSums(is.na(X)) == p)) X[r, 1] <- X[1, 1][!is.na(X[1, 1])][1]
  wt <- if (rep %% 5 == 0) round(runif(n, 0, 3), 2) else NULL
  parms <- NULL
  if (rep %% 3 == 1) parms <- list(split = "information")
  if (rep %% 3 == 2) {
    ls <- matrix(round(runif(K * K, 0.5, 3), 1), K, K); diag(ls) <- 0
    parms <- list(prior = priors[[K]], loss = ls, split = if (rep %% 2 == 0) "information" else "gini")
  }
  if (rep %% 7 == 3) parms <- list(prior = priors[[K]])
  ctl <- list(minsplit = sample(c(6, 10, 20), 1), minbucket = sample(c(2, 4, 7), 1), cp = sample(c(0.002, 0.01, 0.03), 1),
              maxcompete = sample(0:4, 1), maxsurrogate = sample(0:5, 1), usesurrogate = sample(0:2, 1), surrogatestyle = sample(0:1, 1),
              maxdepth = sample(c(3, 5, 30), 1), xval = sample(c(0, 5, 10), 1))
  nn <- 25; nd <- X[sample(n, nn, replace = TRUE), , drop = FALSE]
  for (j in seq_len(p)) if (!fx[j]) nd[[j]] <- round(nd[[j]] + rnorm(nn) * 0.02, 3)
  if (p > 1) nd[sample(nn, 5), sample(p, 1)] <- NA
  nd <- nd[rowSums(is.na(nd)) < p, , drop = FALSE]
  seed <- sample(1:100000, 1)
  cases <- c(cases, rp_cases(y, X, wt = wt, parms = parms, ctl = ctl, seed = seed, newX = nd, prunes = c(ctl$cp * 4)))
}
emit("rpartfull_b", "rpart", list(cases))
