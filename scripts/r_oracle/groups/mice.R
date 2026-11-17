# mice: norm.nob, norm, norm.predict and pmm (method 3) after set.seed; args (n, p, m, maxit, method (0 norm.nob, 1 norm, 2 norm.predict), seed, data[n*p] column-major with NaN, idx): imp values in the order of columns with missing values, imputations, rows
suppressMessages(library(mice))
cases <- list()
set.seed(20261116)
meths <- c("norm.nob", "norm", "norm.predict", "pmm")
for (rep in 1:80) {
  n <- sample(20:60, 1); p <- sample(3:5, 1); m <- sample(1:3, 1); maxit <- sample(1:4, 1); me <- (rep - 1) %% 4
  B <- matrix(rnorm(p * p), p, p); X <- round(matrix(rnorm(n * p), n, p) %*% B + 5 * rep(1, n) %o% runif(p, 1, 3), 4)
  nmc <- sample(1:min(2, p), 1); cols <- sample(p, nmc)
  for (j in cols) X[sample(n, sample(2:max(3, n %/% 5), 1)), j] <- NA
  df <- as.data.frame(X); seed <- sample(1:100000, 1)
  imp <- tryCatch(suppressWarnings(mice(df, m = m, maxit = maxit, method = meths[me + 1], seed = seed, printFlag = FALSE)), error = function(e) NULL)
  if (is.null(imp) || !is.null(imp$loggedEvents)) next
  flat <- unlist(lapply(seq_len(p), function(j) if (!is.null(imp$imp[[j]]) && nrow(imp$imp[[j]]) > 0) as.vector(as.matrix(imp$imp[[j]])) else NULL))
  xa <- ifelse(is.na(X), NaN, X)
  for (q in seq_along(flat)) cases[[length(cases) + 1]] <- case("imp", c(n, p, m, maxit, me, seed, as.vector(xa), q - 1), flat[q], rel = 1e-6, abs = 1e-8)
}
emit("mice", "mice", list(cases))
