# VIM::kNN with mixed numeric and categorical distance columns (unordered factors), one target variable
# that is numeric or categorical, and complete distance columns.
#   args: (n, p, v, k, use_mean, isfac[p] 0/1, x[n*p] row-major with NaN for the missing target values;
#          a categorical column holds its integer code 0..L-1)
#   fn "mix": the weighted sum of the filled target column, sum(filled[i] * (i + 1)) over the rows,
#          accumulated in a double-precision loop in the fixture's order
suppressMessages(library(VIM))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("mix", args, want, rel = 0, abs = 0)
# maxCat samples when two donor values tie, so keep only draws where the answer does not depend on the seed
stable <- function(d, target, k, um) {
  set.seed(101)
  a <- suppressWarnings(kNN(d, variable = target, k = k, numFun = if (um) mean else median,
                            catFun = VIM::maxCat, imp_var = FALSE))
  set.seed(202)
  b <- suppressWarnings(kNN(d, variable = target, k = k, numFun = if (um) mean else median,
                            catFun = VIM::maxCat, imp_var = FALSE))
  identical(as.data.frame(a), as.data.frame(b))
}
set.seed(20261214)
for (rep in 1:200) {
  if (length(cases) >= 30) break
  n <- sample(15:40, 1); p <- sample(3:5, 1); k <- sample(1:5, 1); um <- rep %% 2
  target_fac <- rep %% 3 == 0
  d <- as.data.frame(matrix(round(rnorm(n * p), 2), n, p))
  # one or two categorical distance columns, never the target column
  nfac <- sample(1:2, 1)
  fac_cols <- sample(setdiff(seq_len(p), 1), min(nfac, p - 1))
  for (c in fac_cols) d[[c]] <- factor(sample(0:2, n, replace = TRUE), levels = 0:2)
  if (target_fac) d[[1]] <- factor(sample(0:2, n, replace = TRUE), levels = 0:2)
  d[sample(n, sample(1:4, 1)), 1] <- NA
  if (!any(is.na(d[[1]]))) next
  if (!stable(d, "V1", k, um)) next
  set.seed(999)
  r <- suppressWarnings(kNN(d, variable = "V1", k = k, numFun = if (um) mean else median,
                            catFun = VIM::maxCat, imp_var = FALSE))
  filled <- as.numeric(r[[1]])
  if (any(is.na(filled))) next
  isfac <- as.numeric(vapply(d, is.factor, logical(1)))
  m <- sapply(d, function(col) if (is.factor(col)) as.numeric(col) else as.numeric(col))
  m[is.na(m)] <- NaN
  xr <- as.vector(t(m))
  s <- 0
  for (i in seq_along(filled)) s <- s + filled[i] * i
  add(c(n, p, 0, k, um, isfac, xr), s)
}
emit("vim_knn_mixed", "VIM", list(cases))
