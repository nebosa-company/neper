# partykit ctree: structure, split points, p values and predictions of conditional inference trees.
#   args: (sel, n, p, yl, minsplit, minbucket, minprob, alpha, bonf, maxdepth, stump, inter, nl[p], x[n*p] column-major, y[n])
#   nl[j] 0 numeric, L factor with codes 0..L-1; yl 0 numeric response, L factor response with codes 0..L-1; maxdepth 1000 means Inf
#   sel 1 node count, 2 sum id*varid, 3 sum id*split (numeric break, or sum (level+1)*child for a factor), 4 sum id*nobs,
#       5 sum id*p.value over inner nodes, 6 sum row*node id of the training rows, 7 sum of the fitted values (mean or class code),
#       8 sum row*node id of x * 1.1 + 0.05 (numeric-only data)
suppressMessages(library(partykit))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261221)
nds <- 0
mk <- function(n, p, nl, yl, signal, dec) {
  X <- lapply(seq_len(p), function(j) if (nl[j] == 0) round(rnorm(n) * 6, dec) else sample(0:(nl[j] - 1), n, TRUE))
  lin <- rep(0, n)
  for (j in signal) {
    if (nl[j] == 0) lin <- lin + 2 * (X[[j]] > median(X[[j]])) else lin <- lin + (X[[j]] %% 2) * 2
  }
  if (yl == 0) y <- round(lin * 2 + rnorm(n) * 2, dec)
  else {
    pr <- plogis(lin - mean(lin)); y <- (if (yl == 2) as.integer(runif(n) < pr) else pmin(yl - 1, as.integer(floor(pr * yl * 1.2 + rnorm(n) * 0.4)))); y <- pmax(0, y)
    if (length(unique(y)) < 2) y[1:2] <- c(0, 1)
  }
  list(X = X, y = y)
}
run <- function(n, p, nl, yl, signal, dec, minsplit, minbucket, minprob, alpha, bonf, maxdepth, stump, inter = FALSE, ysc = 1) {
  d <- mk(n, p, nl, yl, signal, dec)
  if (ysc != 1) d$y <- d$y * ysc
  df <- data.frame(lapply(seq_len(p), function(j) if (nl[j] == 0) d$X[[j]] else factor(d$X[[j]], levels = 0:(nl[j] - 1))))
  names(df) <- paste0("v", seq_len(p))
  df$y <- if (yl == 0) d$y else factor(d$y, levels = 0:(yl - 1))
  ct <- ctree_control(minsplit = minsplit, minbucket = minbucket, minprob = minprob, alpha = alpha,
                      testtype = if (bonf) "Bonferroni" else "Univariate", maxdepth = if (maxdepth >= 1000) Inf else maxdepth, stump = stump, intersplit = inter)
  t <- ctree(y ~ ., data = df, control = ct)
  ids <- nodeids(t)
  nodes <- nodeapply(t, ids, function(nd) nd)
  vid <- brk <- nob <- pv <- numeric(length(ids))
  for (i in seq_along(ids)) {
    nd <- nodes[[i]]
    nob[i] <- nrow(data_party(t, ids[i]))
    if (!is.terminal(nd)) {
      sp <- split_node(nd)
      vid[i] <- varid_split(sp) - 1
      pv[i] <- info_node(nd)$p.value
      if (nl[vid[i]] == 0) brk[i] <- breaks_split(sp)
      else { ix <- index_split(sp); brk[i] <- sum((seq_along(ix)) * ifelse(is.na(ix), 0, ix)) }
    }
  }
  if (is.null(nob) || any(is.na(nob))) nob[is.na(nob)] <- 0
  pn <- predict(t, type = "node")
  fit <- predict(t, type = "response")
  fit <- if (yl == 0) as.numeric(fit) else as.integer(as.character(fit))
  a0 <- c(n, p, yl, minsplit, minbucket, minprob, alpha, bonf, maxdepth, stump, inter, nl, unlist(d$X), d$y)
  add("ct", c(1, a0), length(ids))
  add("ct", c(2, a0), sum(ids * vid))
  add("ct", c(3, a0), sum(ids * brk))
  add("ct", c(4, a0), sum(ids * nob))
  add("ct", c(5, a0), sum(ids * pv))
  add("ct", c(6, a0), sum(seq_len(n) * pn))
  add("ct", c(7, a0), sum(fit))
  # as.party / as.constparty round trip: the converted tree keeps node ids and fitted values (sel 9 = sel 6, sel 10 = sel 7)
  pt <- party(node_party(t), data = model.frame(y ~ ., df)); cp <- as.constparty(pt)
  add("ct", c(9, a0), sum(seq_len(n) * predict(cp, type = "node")))
  fcp <- predict(cp, type = "response")
  add("ct", c(10, a0), sum(if (yl == 0) as.numeric(fcp) else as.integer(as.character(fcp))))
  if (all(nl == 0)) {
    nd2 <- df; for (j in seq_len(p)) nd2[[j]] <- nd2[[j]] * 1.1 + 0.05
    add("ct", c(8, a0), sum(seq_len(n) * predict(t, newdata = nd2, type = "node")))
  }
}
for (rep in 1:30) {
  n <- sample(40:90, 1); p <- sample(2:5, 1)
  nl <- sapply(seq_len(p), function(j) if (rep %% 3 == 0) sample(c(0, 3, 4, 5), 1) else sample(c(0, 0, 2, 3, 4), 1))
  if (rep %% 5 == 1) nl[] <- 0
  yl <- c(0, 0, 2, 3, 4, 0)[(rep %% 6) + 1]
  signal <- sort(sample(seq_len(p), sample(1:min(2, p), 1)))
  run(n, p, nl, yl, signal, if (rep %% 7 == 0) 1 else 0,
      minsplit = c(20, 10, 20, 30)[(rep %% 4) + 1], minbucket = c(7, 3, 7, 10)[((rep + 1) %% 4) + 1], minprob = 0.01,
      alpha = c(0.05, 0.2, 0.05, 0.5)[(rep %% 4) + 1], bonf = rep %% 3 != 1, maxdepth = c(1000, 1000, 2, 3)[(rep %% 4) + 1], stump = rep == 17, inter = rep %% 2 == 0)
}
# response on a tiny scale: the split statistic's covariance sits at the 1.49e-8 singularity tolerance (tolv), split in R above it, no split below
for (rep in 1:8) {
  n <- 60; p <- 2; nl <- c(0, 0)
  run(n, p, nl, 0, 1, 0, minsplit = 20, minbucket = 7, minprob = 0.01, alpha = 0.05, bonf = TRUE, maxdepth = 1000, stump = FALSE,
      ysc = c(1e-4, 5e-5, 3.5e-5, 3e-5, 2.5e-5, 2e-5, 1e-5, 4e-5)[rep])
}
emit("partykit", "partykit", list(cases))
