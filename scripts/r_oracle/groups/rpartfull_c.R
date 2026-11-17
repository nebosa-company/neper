# rpart methods "poisson" (cbind(time, events)) and "exp" (Surv): the shrinkage parameter, the deviance and sqrt xval rules, weights, factor predictors, missing values.
# Layout of the cases: scripts/r_oracle/rpartfull_lib.R.
source(file.path(root, "scripts", "r_oracle", "rpartfull_lib.R"))
cases <- list()
set.seed(20266103)
for (rep in 1:40) {
  n <- sample(50:130, 1); p <- sample(2:4, 1)
  X <- data.frame(row.names = seq_len(n))
  for (j in seq_len(p)) {
    if (runif(1) < 0.3) X[[paste0("x", j)]] <- rp_fac(sample.int(L <- sample(2:5, 1), n, replace = TRUE), L)
    else X[[paste0("x", j)]] <- round(runif(n), 3)
  }
  fx <- vapply(X, is.factor, TRUE)
  lin <- rep(0, n)
  for (j in seq_len(p)) lin <- lin + if (fx[j]) (as.integer(X[[j]]) %% 2) * 0.9 else 1.4 * (X[[j]] > 0.5)
  if (rep %% 4 == 0) for (j in sample(p, max(1, p - 1))) X[[j]][sample(n, round(n * 0.1))] <- NA
  for (r in which(rowSums(is.na(X)) == p)) X[r, 1] <- X[1, 1][!is.na(X[1, 1])][1]
  wt <- if (rep %% 5 == 0) round(runif(n, 0.2, 3), 2) else NULL
  ctl <- list(minsplit = sample(c(6, 10, 20), 1), minbucket = sample(c(3, 5, 7), 1), cp = sample(c(0.003, 0.01, 0.03), 1),
              maxcompete = sample(0:4, 1), maxsurrogate = sample(0:5, 1), usesurrogate = sample(0:2, 1), surrogatestyle = sample(0:1, 1),
              maxdepth = sample(c(3, 5, 30), 1), xval = sample(c(0, 5, 10), 1))
  nn <- 25; nd <- X[sample(n, nn, replace = TRUE), , drop = FALSE]
  for (j in seq_len(p)) if (!fx[j]) nd[[j]] <- round(nd[[j]] + rnorm(nn) * 0.02, 3)
  if (p > 1) nd[sample(nn, 5), sample(p, 1)] <- NA
  nd <- nd[rowSums(is.na(nd)) < p, , drop = FALSE]
  seed <- sample(1:100000, 1)
  parms <- NULL
  if (rep %% 3 == 1) parms <- list(shrink = sample(c(0, 0.5, 2), 1))
  if (rep %% 3 == 2) parms <- list(method = "sqrt", shrink = sample(c(0, 1, 3), 1))
  if (rep %% 7 == 3) parms <- list(method = "deviance")
  if (rep <= 20) {
    tm <- round(runif(n, 0.2, 3), 2)
    ev <- rpois(n, tm * exp(lin * 0.7 - 0.5))
    y <- cbind(tm, ev)
    cases <- c(cases, rp_cases(y, X, wt = wt, method = "poisson", parms = parms, ctl = ctl, seed = seed, newX = nd, prunes = c(ctl$cp * 4)))
  } else {
    tm <- round(rexp(n, exp(-0.6 * lin + 0.2)) * 3 + 0.05, 2)
    st <- as.integer(runif(n) < 0.7)
    if (all(st == 0)) st[1] <- 1
    y <- Surv(tm, st)
    cases <- c(cases, rp_cases(y, X, wt = wt, parms = parms, ctl = ctl, seed = seed, newX = nd, prunes = c(ctl$cp * 4)))
  }
}
emit("rpartfull_c", c("rpart", "survival"), list(cases))
