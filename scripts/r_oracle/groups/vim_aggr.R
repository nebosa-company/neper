# VIM::aggr with plot = FALSE: the per-column missing counts, the missingness patterns of the rows in
# table() order, their counts and percentages.
#   args: (n, p, x[n*p] row-major with NaN for the missing values)
#   fn "aggr": sum of (per-column counts, the pattern bits pattern by pattern, the pattern counts, the
#   percentages) times its 1-based position, accumulated in a double loop in the fixture's order
suppressMessages(library(VIM))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("aggr", args, want, rel = 0, abs = 0)
set.seed(20261217)
for (rep in 1:30) {
  n <- sample(10:40, 1); p <- sample(2:6, 1)
  d <- as.data.frame(matrix(round(rnorm(n * p), 2), n, p))
  for (c in seq_len(p)) {
    if (runif(1) < 0.6) d[sample(n, sample(1:max(1, floor(n / 3)), 1)), c] <- NA
  }
  a <- suppressWarnings(aggr(d, plot = FALSE))
  vals <- c(a$missings$Count, as.vector(t(a$tabcomb)), a$count, a$percent)
  s <- 0
  for (i in seq_along(vals)) s <- s + vals[i] * i
  m <- as.matrix(d)
  m[is.na(m)] <- NaN
  add(c(n, p, as.vector(t(m))), s)
}
emit("vim_aggr", "VIM", list(cases))
