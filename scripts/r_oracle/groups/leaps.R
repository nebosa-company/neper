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
emit("leaps", "leaps", list(cases))
