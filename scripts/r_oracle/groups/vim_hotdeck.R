# VIM::hotdeck over every numeric column, with the random row order (ord_var = NULL), one domain and
# imp_var = FALSE. A missing value takes the value of the row before it in the runif order, stepping
# back while the donor is missing too.
#   args: (seed, n, p, x[n*p] row-major with NaN for the missing values)
#   fn "hd": the weighted sum of the filled matrix, sum(filled_rm[k] * k) over its row-major order
suppressMessages(library(VIM))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("hd", args, want, rel = 0, abs = 0)
set.seed(20261213)
for (rep in 1:30) {
  n <- sample(12:45, 1); p <- sample(2:5, 1); sd0 <- sample(1:100000, 1)
  d <- as.data.frame(matrix(round(rnorm(n * p), 2), n))
  for (c in seq_len(p)) {
    if (runif(1) < 0.6) d[sample(n, sample(1:5, 1)), c] <- NA
    # a column with no observed value has no donor at all and VIM stops, so keep one
    if (all(is.na(d[[c]]))) d[sample(n, 1), c] <- 0
  }
  if (!any(is.na(d))) d[sample(n, 1), sample(p, 1)] <- NA
  set.seed(sd0)
  r <- suppressWarnings(hotdeck(d, imp_var = FALSE))
  filled <- as.matrix(r)
  if (any(is.na(filled))) stop("hotdeck left a missing value")
  rm <- as.vector(t(filled))
  # the fixture's own accumulation order (one double-precision add per cell), so the comparison can be exact
  s <- 0
  for (k in seq_along(rm)) s <- s + rm[k] * k
  add(c(sd0, n, p, as.vector(t(as.matrix(d)))), s)
}
emit("vim_hotdeck", "VIM", list(cases))
