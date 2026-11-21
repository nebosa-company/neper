# partykit cforest under set.seed with factor predictors: forest predictions on newdata. A level a node never saw has no kid, so predict draws one (sample with the share of each kid), in fitted_node's order.
#   args: (sel, seed, n, p, yl, ntree, mtry, minsplit, minbucket, nn, nl[p], x[n*p], y[n], xnew[nn*p])
#   nl[j] 0 numeric, L factor with codes 0..L-1; yl 0 numeric response, L factor response with codes 0..L-1
#   sel 1 sum of predictions (class codes for a factor), 2 sum j*pred_j, 3 first, 4 last
suppressMessages(library(partykit))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261251)
for (rep in 1:24) {
  n <- sample(50:100, 1); p <- sample(3:6, 1); yl <- c(0, 0, 2, 3, 0, 2, 4)[(rep %% 7) + 1]
  nl <- sapply(seq_len(p), function(j) sample(c(0, 4, 5, 6, 8), 1)); nl[1] <- sample(c(4, 5, 6, 8), 1)
  gen <- function(m) sapply(seq_len(p), function(j) if (nl[j] == 0) round(rnorm(m) * 6) else sample(0:(nl[j] - 1), m, TRUE))
  X <- gen(n); XN <- gen(15); nn <- 15
  for (j in seq_len(p)) if (nl[j] > 0) X[seq_len(nl[j]), j] <- 0:(nl[j] - 1)
  lin <- 2 * (X[, 1] %% 2) + (if (nl[2] == 0) (X[, 2] > 1) * 1.5 else (X[, 2] %% 2) * 1.5)
  y <- if (yl == 0) round(lin + rnorm(n), 1) else pmin(yl - 1, as.integer(floor(plogis(lin - 1.2) * yl * 1.1 + runif(n) * 0.4)))
  if (yl > 0 && length(unique(y)) < 2) y[1:2] <- c(0, 1)
  mk <- function(M) { d <- as.data.frame(M); names(d) <- paste0("v", 1:p); for (j in seq_len(p)) if (nl[j] > 0) d[[j]] <- factor(d[[j]], levels = 0:(nl[j] - 1)); d }
  df <- mk(X); df$y <- if (yl == 0) y else factor(y, levels = 0:(yl - 1)); nd <- mk(XN)
  ntree <- sample(c(6, 10, 15), 1); mtry <- sample(1:p, 1)
  minsplit <- c(20, 10)[(rep %% 2) + 1]; minbucket <- c(7, 4)[(rep %% 2) + 1]
  seed <- sample(1:100000, 1)
  set.seed(seed)
  f <- cforest(y ~ ., data = df, ntree = ntree, mtry = mtry, minsplit = minsplit, minbucket = minbucket)
  pr <- predict(f, newdata = nd)
  pr <- if (yl == 0) as.numeric(pr) else as.integer(as.character(pr))
  a0 <- c(seed, n, p, yl, ntree, mtry, minsplit, minbucket, nn, nl, X, y, XN)
  add("cf", c(1, a0), sum(pr)); add("cf", c(2, a0), sum(seq_len(nn) * pr)); add("cf", c(3, a0), pr[1]); add("cf", c(4, a0), pr[nn])
}
emit("partykitforestf", "partykit", list(cases))
