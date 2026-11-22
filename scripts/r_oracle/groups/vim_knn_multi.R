# VIM::kNN with several target variables in one call: the columns in `variable` are filled in that order,
# and a later target's distances already see the values filled for the earlier ones (useImputedDist).
#   args: (n, p, nvars, vars[nvars] 0-based column indices, k, use_mean, isfac[p] 0/1, x[n*p] row-major
#          with NaN for the missing values; a categorical column holds its integer code 0..L-1)
#   fn "multi": sum over the rows, and inside a row over the target columns in `vars` order, of the
#          filled value times its 1-based position in that sequence, accumulated in a double loop
suppressMessages(library(VIM))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("multi", args, want, rel = 0, abs = 0)
vars <- c("V1", "V2")
stable <- function(d, k, um) {
  set.seed(101)
  a <- suppressWarnings(kNN(d, variable = vars, k = k, numFun = if (um) mean else median,
                            catFun = VIM::maxCat, imp_var = FALSE))
  set.seed(202)
  b <- suppressWarnings(kNN(d, variable = vars, k = k, numFun = if (um) mean else median,
                            catFun = VIM::maxCat, imp_var = FALSE))
  identical(as.data.frame(a), as.data.frame(b))
}
set.seed(20261216)
for (rep in 1:400) {
  if (length(cases) >= 30) break
  n <- sample(15:35, 1); p <- sample(4:6, 1); k <- sample(1:5, 1); um <- rep %% 2
  d <- as.data.frame(matrix(round(rnorm(n * p), 2), n, p))
  # V2 tracks V1 on half the draws, so V1's imputed values decide V2's donors and the order matters
  if (rep %% 2 == 0) d[[2]] <- round(0.8 * d[[1]] + rnorm(n, 0, 0.15), 2)
  # one or two categorical columns among all columns; a categorical target is a factor too
  nfac <- sample(1:2, 1)
  fac_cols <- sample(seq_len(p), nfac)
  for (c in fac_cols) d[[c]] <- factor(sample(0:2, n, replace = TRUE), levels = 0:2)
  # missing values in both targets (V1 heavily missing, so its imputed values weigh on V2's distances),
  # and sometimes in a distance column
  d[sample(n, max(2, round(n * runif(1, 0.2, 0.4)))), 1] <- NA
  d[sample(n, sample(1:3, 1)), 2] <- NA
  extra <- setdiff(seq_len(p), 1:2)
  if (length(extra) > 0 && runif(1) < 0.6) d[[sample(extra, 1)]][sample(n, sample(1:3, 1))] <- NA
  if (!any(is.na(d[[1]])) || !any(is.na(d[[2]]))) next
  if (!stable(d, k, um)) next
  set.seed(999)
  r <- suppressWarnings(kNN(d, variable = vars, k = k, numFun = if (um) mean else median,
                            catFun = VIM::maxCat, imp_var = FALSE))
  filled <- as.matrix(sapply(r[1:2], as.numeric))
  if (any(is.na(filled))) next
  isfac <- as.numeric(vapply(d, is.factor, logical(1)))
  m <- sapply(d, function(col) if (is.factor(col)) as.numeric(col) else as.numeric(col))
  m[is.na(m)] <- NaN
  xr <- as.vector(t(m))
  vals <- as.vector(t(filled))
  s <- 0
  for (i in seq_along(vals)) s <- s + vals[i] * i
  add(c(n, p, length(vars), 0, 1, k, um, isfac, xr), s)
}
emit("vim_knn_multi", "VIM", list(cases))
