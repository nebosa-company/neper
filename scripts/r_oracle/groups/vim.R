# VIM::kNN on one numeric variable (column 1) with complete distance columns; numFun median or mean.
#   args: (n, p, k, use_mean, x[n*p] row-major with NaN for the missing values of column 1)
#   fn "fill" (the filled column weighted by position)
suppressMessages(library(VIM))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-10, abs = 1e-12)
set.seed(20261212)
for (rep in 1:40) {
  n <- sample(15:60, 1); p <- sample(3:6, 1); k <- sample(1:7, 1); um <- rep %% 2
  d <- as.data.frame(matrix(round(rnorm(n * p), 2), n)); d[sample(n, sample(1:4, 1)), 1] <- NA
  r <- suppressWarnings(kNN(d, variable = "V1", k = k, numFun = if (um) mean else median, imp_var = FALSE))
  add("fill", c(n, p, k, um, as.vector(t(as.matrix(d)))), sum(r$V1 * seq_len(n)))
}
emit("vim", "VIM", list(cases))
