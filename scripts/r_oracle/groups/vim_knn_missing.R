# VIM::kNN with missing values in the distance columns (gowerD replaces them with the column's largest
# prepared value plus one), mixed numeric and categorical distance columns, one target variable.
#   args: (n, p, v, k, use_mean, isfac[p] 0/1, x[n*p] row-major with NaN for the missing target values
#          and for the missing distance values; a categorical column holds its integer code 0..L-1)
#   fn "miss": the weighted sum of the filled target column, sum(filled[i] * (i + 1)), accumulated in a
#          double-precision loop in the fixture's order
suppressMessages(library(VIM))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("miss", args, want, rel = 0, abs = 0)
stable <- function(d, k, um) {
  set.seed(101)
  a <- suppressWarnings(kNN(d, variable = "V1", k = k, numFun = if (um) mean else median,
                            catFun = VIM::maxCat, imp_var = FALSE))
  set.seed(202)
  b <- suppressWarnings(kNN(d, variable = "V1", k = k, numFun = if (um) mean else median,
                            catFun = VIM::maxCat, imp_var = FALSE))
  identical(as.data.frame(a), as.data.frame(b))
}
set.seed(20261215)
for (rep in 1:400) {
  if (length(cases) >= 30) break
  n <- sample(15:40, 1); p <- sample(3:5, 1); k <- sample(1:5, 1); um <- rep %% 2
  target_fac <- rep %% 3 == 0
  d <- as.data.frame(matrix(round(rnorm(n * p), 2), n, p))
  nfac <- sample(1:2, 1)
  fac_cols <- sample(setdiff(seq_len(p), 1), min(nfac, p - 1))
  for (c in fac_cols) d[[c]] <- factor(sample(0:2, n, replace = TRUE), levels = 0:2)
  if (target_fac) d[[1]] <- factor(sample(0:2, n, replace = TRUE), levels = 0:2)
  # missing distance values: one column may lose every value, which gowerD answers with 1
  for (c in setdiff(seq_len(p), 1)) {
    if (runif(1) < 0.5) {
      rows <- sample(n, sample(1:4, 1))
      d[[c]][rows] <- NA
      if (runif(1) < 0.15) d[[c]][] <- NA
    }
  }
  d[sample(n, sample(1:4, 1)), 1] <- NA
  if (!any(is.na(d[[1]]))) next
  if (!any(is.na(d[, setdiff(seq_len(p), 1), drop = FALSE]))) next
  if (!stable(d, k, um)) next
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
emit("vim_knn_missing", "VIM", list(cases))
