# partykit plain ctree with mtry (random variables per node on set.seed(seed)'s stream) and maxvar (cap on the distinct split variables).
#   args: (sel, n, p, yl, minsplit, minbucket, minprob, mincrit, bonf, statcrit, maxst, maxdepth, stump, inter, seed, nres, spl, mtry, maxvar, nl[p], w[n], x[n*p] column-major, y[n])
#   nl[j] 0 numeric, L>0 unordered factor with codes 0..L-1, -L ordered factor with codes 0..L-1; yl 0 numeric response, L factor response; maxdepth 1000 means Inf
#   statcrit 1: testtype Teststatistic (mincrit is mincriterion); maxst 1: teststat = splitstat = "maximum"; w the integer case weights
#   sel 1 node count, 2 sum id*varid, 3 sum id*split (numeric break, ordered level index, or sum (level+1)*child), 4 sum id*sum of weights, 5 sum id*p.value over inner nodes (not for Teststatistic),
#       6 sum row*node id of the training rows, 7 sum of the fitted values, 11 sum id*statistic of the split variable over inner nodes
suppressMessages(library(partykit))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261601)
mk <- function(n, p, nl, yl, dec) {
  X <- lapply(seq_len(p), function(j) if (nl[j] == 0) round(rnorm(n) * 6, dec) else sample(0:(abs(nl[j]) - 1), n, TRUE))
  sg <- sort(sample(seq_len(p), sample(1:min(2, p), 1)))
  lin <- rep(0, n)
  for (j in sg) {
    if (nl[j] == 0) lin <- lin + 2 * (X[[j]] > median(X[[j]]))
    else if (nl[j] < 0) lin <- lin + 2 * X[[j]] / max(1, abs(nl[j]) - 1)
    else lin <- lin + (X[[j]] %% 2) * 2
  }
  if (yl == 0) y <- round(lin * 2 + rnorm(n) * 2, dec)
  else {
    pr <- plogis(lin - mean(lin)); y <- (if (yl == 2) as.integer(runif(n) < pr) else pmin(yl - 1, as.integer(floor(pr * yl * 1.2 + rnorm(n) * 0.4)))); y <- pmax(0, y)
    if (length(unique(y)) < 2) y[1:2] <- c(0, 1)
  }
  list(X = X, y = y)
}
run <- function(n, p, nl, yl, dec, seed, nres, spl, mtry, maxvar, minsplit, minbucket, minprob, mincrit, bonf, statcrit, maxst, maxdepth, stump, inter, w = rep(1, n)) {
  d <- mk(n, p, nl, yl, dec)
  df <- data.frame(lapply(seq_len(p), function(j) if (nl[j] == 0) d$X[[j]] else factor(d$X[[j]], levels = 0:(abs(nl[j]) - 1), ordered = nl[j] < 0)))
  names(df) <- paste0("v", seq_len(p))
  df$y <- if (yl == 0) d$y else factor(d$y, levels = 0:(yl - 1))
  tt <- if (statcrit) "Teststatistic" else if (bonf && nres > 0) c("Bonferroni", "MonteCarlo") else if (nres > 0) "MonteCarlo" else if (bonf) "Bonferroni" else "Univariate"
  mx <- if (maxst) "maximum" else "quadratic"
  ct <- ctree_control(minsplit = minsplit, minbucket = minbucket, minprob = minprob, mincriterion = mincrit, teststat = mx, splitstat = mx,
                      testtype = tt, splittest = spl, nresample = max(nres, 1L), mtry = if (mtry == 0) Inf else mtry, maxvar = if (maxvar >= 1000000) Inf else maxvar, maxdepth = if (maxdepth >= 1000) Inf else maxdepth, stump = stump, intersplit = inter)
  set.seed(seed)
  t <- ctree(y ~ ., data = df, weights = as.integer(w), control = ct)
  ids <- nodeids(t)
  pn <- predict(t, type = "node")
  vid <- brk <- nob <- pv <- st <- numeric(length(ids))
  for (i in seq_along(ids)) {
    nd <- nodeapply(t, ids[i], function(z) z)[[1]]
    nob[i] <- sum(w[pn %in% nodeids(t, from = ids[i], terminal = TRUE)])
    if (!is.terminal(nd)) {
      sp <- split_node(nd)
      vid[i] <- varid_split(sp) - 1
      pv[i] <- if (statcrit) 0 else info_node(nd)$p.value
      cr <- info_node(nd)$criterion
      st[i] <- cr["statistic", paste0("v", vid[i])]
      if (nl[vid[i]] == 0) brk[i] <- breaks_split(sp)
      else if (nl[vid[i]] < 0) brk[i] <- breaks_split(sp)
      else { ix <- index_split(sp); brk[i] <- sum((seq_along(ix)) * ifelse(is.na(ix), 0, ix)) }
    }
  }
  fit <- predict(t, type = "response")
  fit <- if (yl == 0) as.numeric(fit) else as.integer(as.character(fit))
  a0 <- c(n, p, yl, minsplit, minbucket, minprob, mincrit, bonf, statcrit, maxst, maxdepth, stump, inter, seed, nres, spl, mtry, maxvar, nl, w, unlist(d$X), d$y)
  add("co", c(1, a0), length(ids))
  add("co", c(2, a0), sum(ids * vid))
  add("co", c(3, a0), sum(ids * brk))
  add("co", c(4, a0), sum(ids * nob))
  if (!statcrit) add("co", c(5, a0), sum(ids * pv))
  add("co", c(6, a0), sum(seq_len(n) * pn))
  add("co", c(7, a0), sum(fit))
  add("co", c(11, a0), sum(ids * st))
}
pickp <- function(rep, kinds) { p <- sample(3:6, 1); list(p = p, nl = sapply(seq_len(p), function(j) sample(kinds, 1))) }
for (rep in 1:48) {
  pp <- pickp(rep, if (rep %% 4 == 0) c(0, 0, 2, 3, 4) else c(0, 0, 2, 3, 5)); n <- sample(60:110, 1)
  mtry <- if (rep %% 3 == 1) 0 else sample(1:pp$p, 1)
  maxvar <- if (rep %% 3 == 0) 1000000 else sample(1:2, 1)
  if (mtry == 0 && maxvar >= 1000000) mtry <- 2
  w <- if (rep %% 5 == 0) sample(1:3, n, TRUE) else rep(1, n)
  run(n, pp$p, pp$nl, c(0, 2, 3, 2, 0, 4)[(rep %% 6) + 1], 0, seed = 3000 + rep, nres = 0, spl = FALSE, mtry = mtry, maxvar = maxvar,
      minsplit = c(20, 10)[(rep %% 2) + 1], minbucket = c(7, 4)[(rep %% 2) + 1], minprob = 0.01,
      mincrit = c(0.95, 0.5)[(rep %% 2) + 1], bonf = rep %% 3 != 2, statcrit = FALSE, maxst = FALSE, maxdepth = c(1000, 4)[(rep %% 2) + 1], stump = FALSE, inter = rep %% 4 == 1, w = w)
}
emit("partykitctl", "partykit", list(cases))
