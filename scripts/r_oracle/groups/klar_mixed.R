# klaR: NaiveBayes with numeric and factor predictors (usekernel = FALSE, fL = 0) and its predict.
#   args: (n, p, k, m, isfac[p] 0/1, maxlev, x row-major n by p (factor columns are 0-based level codes),
#          labels[n] (1..k), test row-major m by p)
#   fn "prior" (sum of apriori * position); "mean" and "sd": the numeric columns' tables in column order,
#      class by class, weighted by position; "fprob": the factor columns' conditional probability tables in
#      column order, class by class, level by level, weighted by position; "post" (posterior);
#      "cls" (predicted class * row position)
suppressMessages(library(klaR))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
wsum <- function(v) { s <- 0; for (i in seq_along(v)) s <- s + v[i] * i; s }
set.seed(20261229)
for (rep in 1:12) {
  n <- sample(40:90, 1); p <- sample(2:4, 1); k <- sample(2:4, 1); m <- 12
  nfac <- sample(1:(p - 1), 1); maxlev <- sample(2:3, 1)
  fac_cols <- sample(seq_len(p), nfac)
  isfac <- as.numeric(seq_len(p) %in% fac_cols)
  g <- factor(sample(rep(1:k, length.out = n)))
  X <- matrix(rnorm(n * p), n, p) + matrix(as.numeric(as.integer(g)), n, p) * 0.7
  T <- matrix(rnorm(m * p) + sample(1:k, m * p, replace = TRUE) * 0.7, m, p)
  for (c in fac_cols) {
    # a level that depends on the class, so the factor carries signal
    X[, c] <- (sample(0:(maxlev - 1), n, replace = TRUE) + as.integer(g) - 1) %% maxlev
    T[, c] <- sample(0:(maxlev - 1), m, replace = TRUE)
  }
  dfx <- as.data.frame(X); names(dfx) <- paste0("v", seq_len(p))
  for (c in fac_cols) dfx[[c]] <- factor(dfx[[c]], levels = 0:(maxlev - 1))
  dft <- as.data.frame(T); names(dft) <- names(dfx)
  for (c in fac_cols) dft[[c]] <- factor(dft[[c]], levels = 0:(maxlev - 1))
  nb <- NaiveBayes(dfx, g, usekernel = FALSE)
  pr <- predict(nb, dft)
  a <- c(n, p, k, m, isfac, maxlev, as.vector(t(X)), as.numeric(g), as.vector(t(T)))
  add("prior", a, wsum(as.vector(nb$apriori)))
  num_cols <- setdiff(seq_len(p), fac_cols)
  if (length(num_cols) > 0) {
    mean_v <- unlist(lapply(num_cols, function(c) nb$tables[[c]][, 1]))
    sd_v <- unlist(lapply(num_cols, function(c) nb$tables[[c]][, 2]))
    add("mean", a, wsum(mean_v))
    add("sd", a, wsum(sd_v))
  }
  fprob_v <- unlist(lapply(fac_cols, function(c) as.vector(t(as.matrix(nb$tables[[c]])))))
  add("fprob", a, wsum(fprob_v))
  add("post", a, wsum(as.vector(t(pr$posterior))))
  add("cls", a, wsum(as.numeric(pr$class)))
}
emit("klar_mixed", "klaR", list(cases))
