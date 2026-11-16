# leaps::regsubsets (nbest = 1): the chosen subset (as a bitmask over the variables), rss, rsq, adjr2, cp, bic of each size.
#   args: (method 0 exhaustive 1 forward 2 backward, n, p, nvmax, X[n*p] column-major, y[n], k, q)  q 0 mask 1 rss 2 rsq 3 adjr2 4 cp 5 bic
suppressMessages(library(leaps))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-9)
set.seed(20261116)
for (rep in 1:30) {
  n <- sample(25:80, 1); p <- sample(4:9, 1)
  X <- matrix(round(rnorm(n * p), 3), n, p); beta <- c(1, -0.8, 0, 0.5, 0, 0.3, 0, 0, 0)[seq_len(p)]
  y <- round(drop(X %*% beta) + rnorm(n), 3); nvmax <- min(p, 6)
  for (method in 0:2) {
    r <- regsubsets(X, y, nvmax = nvmax, method = c("exhaustive", "forward", "backward")[method + 1])
    s <- summary(r)
    for (k in seq_len(nvmax)) {
      mask <- sum(2^(which(s$which[k, -1]) - 1))
      vals <- c(mask, s$rss[k], s$rsq[k], s$adjr2[k], s$cp[k], s$bic[k])
      for (q in 1:6) add("rs", c(method, n, p, nvmax, X, y, k, q - 1), vals[q])
    }
  }
}
# nbest > 1 with force.in and force.out (exhaustive): every row of summary(); k size incl. forced, j position within the size
#   fn "rs2": (n, p, nvmax, nbest, force.in mask, force.out mask, X[n*p], y[n], k, j, q)  q 0 mask 1 rss 2 rsq 3 adjr2 4 cp 5 bic
for (rep in 1:40) {
  n <- sample(25:70, 1); p <- sample(4:8, 1)
  X <- matrix(round(rnorm(n * p), 3), n, p); beta <- c(1, -0.8, 0, 0.5, 0, 0.3, 0, 0)[seq_len(p)]
  y <- round(drop(X %*% beta) + rnorm(n), 3); nvmax <- sample(2:min(p, 6), 1); nbest <- sample(1:4, 1)
  fin <- if (rep %% 2 == 0) sample(p, sample(0:1, 1)) else integer(0)
  fout <- if (rep %% 3 == 0) sample(setdiff(seq_len(p), fin), 1) else integer(0)
  r <- tryCatch(regsubsets(X, y, nbest = nbest, nvmax = nvmax, force.in = if (length(fin)) fin else NULL, force.out = if (length(fout)) fout else NULL), error = function(e) NULL)
  if (is.null(r)) next
  s <- summary(r); pos <- list()
  for (row in seq_along(s$rss)) {
    k <- as.integer(rownames(s$which)[row]); pos[[as.character(k)]] <- (if (is.null(pos[[as.character(k)]])) 0 else pos[[as.character(k)]]) + 1
    wh <- s$which[row, -1]; mask <- sum(2^(utf8ToInt(paste(names(wh)[wh], collapse = "")) - 97))
    vals <- c(mask, s$rss[row], s$rsq[row], s$adjr2[row], s$cp[row], s$bic[row])
    for (q in 1:6) add("rs2", c(n, p, nvmax, nbest, sum(2^(fin - 1)), sum(2^(fout - 1)), X, y, k, pos[[as.character(k)]] - 1, q - 1), vals[q])
  }
}
# method = "seqrep" (nbest = 1), with force.in and force.out; nbest 0 in the args stands for it
for (rep in 1:60) {
  n <- sample(25:70, 1); p <- sample(4:8, 1)
  X <- matrix(round(rnorm(n * p), 3), n, p); beta <- c(1, -0.8, 0, 0.5, 0, 0.3, 0, 0)[seq_len(p)]
  y <- round(drop(X %*% beta) + rnorm(n), 3)
  fin <- if (rep %% 2 == 0) sample(p, sample(0:1, 1)) else integer(0)
  fout <- if (rep %% 3 == 0) sample(setdiff(seq_len(p), fin), 1) else integer(0)
  nvmax <- sample(2:p, 1)
  r <- tryCatch(regsubsets(X, y, nvmax = nvmax, method = "seqrep", force.in = if (length(fin)) fin else NULL, force.out = if (length(fout)) fout else NULL), error = function(e) NULL)
  if (is.null(r)) next
  s <- summary(r)
  for (row in seq_along(s$rss)) {
    k <- as.integer(rownames(s$which)[row])
    wh <- s$which[row, -1]; mask <- sum(2^(utf8ToInt(paste(names(wh)[wh], collapse = "")) - 97))
    vals <- c(mask, s$rss[row], s$rsq[row], s$adjr2[row], s$cp[row], s$bic[row])
    for (q in 1:6) add("rs2", c(n, p, nvmax, 0, sum(2^(fin - 1)), sum(2^(fout - 1)), X, y, k, 0, q - 1), vals[q])
  }
}
emit("leaps", "leaps", list(cases))
