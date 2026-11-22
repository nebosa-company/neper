# VIM::kNN with ordered and semi-continuous distance columns (mixed = the spike columns, mixed.constant = 0),
# one target variable that is numeric or a factor.
#   args: (n, p, k, use_mean, kind[p] (0 numeric 1 factor 2 ordered 3 semi-continuous), nlev[p], mconst[p],
#          x[n*p] row-major with NaN for the missing target values; ordered and factor columns hold 0-based
#          level codes, and a semi-continuous column holds its spike as 0)
#   fn "kinds": the weighted sum of the filled target column, sum(filled[i] * (i + 1)), accumulated in a
#          double-precision loop
suppressMessages(library(VIM))
cases <- list()
# R's mean() sums in long double, so the mean path is allowed one ulp; the median path is exact
add <- function(args, want, rel = 0) cases[[length(cases) + 1]] <<- case("kinds", args, want, rel = rel, abs = 0)
stable <- function(d, k, um) {
  set.seed(101)
  a <- suppressWarnings(kNN(d, variable = "V1", k = k, numFun = if (um) mean else median,
                            catFun = VIM::maxCat, mixed = "V4", imp_var = FALSE))
  set.seed(202)
  b <- suppressWarnings(kNN(d, variable = "V1", k = k, numFun = if (um) mean else median,
                            catFun = VIM::maxCat, mixed = "V4", imp_var = FALSE))
  identical(as.data.frame(a), as.data.frame(b))
}
set.seed(20270104)
for (rep in 1:300) {
  if (length(cases) >= 30) break
  n <- sample(15:40, 1); p <- 5; k <- sample(1:5, 1); um <- rep %% 2
  d <- data.frame(V1 = round(rnorm(n), 2))
  d$V2 <- round(rnorm(n), 2)
  d$V3 <- factor(sample(0:2, n, replace = TRUE), levels = 0:2)
  d$V4 <- round(abs(rnorm(n)), 2); d$V4[sample(n, max(2, round(n / 3)))] <- 0
  d$V5 <- factor(sample(0:2, n, replace = TRUE), levels = 0:2, ordered = TRUE)
  if (rep %% 3 == 0) d$V1 <- factor(sample(0:2, n, replace = TRUE), levels = 0:2)
  d[sample(n, sample(1:4, 1)), 1] <- NA
  if (!any(is.na(d[[1]]))) next
  if (!stable(d, k, um)) next
  set.seed(999)
  r <- suppressWarnings(kNN(d, variable = "V1", k = k, numFun = if (um) mean else median,
                            catFun = VIM::maxCat, mixed = "V4", imp_var = FALSE))
  filled <- as.numeric(r[[1]])
  if (any(is.na(filled))) next
  kind <- c(if (is.factor(d$V1)) 1 else 0, 0, 1, 3, 2)
  nlev <- c(0, 0, 3, 0, 3)
  mconst <- c(0, 0, 0, 0, 0)
  m <- sapply(d, function(col) if (is.factor(col)) as.numeric(col) else as.numeric(col))
  m[is.na(m)] <- NaN
  xr <- as.vector(t(m))
  s <- 0
  for (i in seq_along(filled)) s <- s + filled[i] * i
  add(c(n, p, k, um, kind, nlev, mconst, xr), s, if (um) 1e-14 else 0)
}
emit("vim_knn_kinds", "VIM", list(cases))
