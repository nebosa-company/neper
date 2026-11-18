# DescTools Mode and Outlier. Args: (kind, n, x[n], j); kind 0 Mode, 1 Outlier boxplot, 2 Outlier hampel; j 0 count of the values, 1 their sum, 2 the
# frequency of the mode (Mode only). Mode returns NA (no case) when every count is one.
suppressMessages(library(DescTools))
cases <- list()
add <- function(fn, args, want, rel = 1e-12, abs = 1e-12) if (length(want) == 1 && is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261232)
for (rep in 1:18) {
  n <- sample(6:30, 1)
  x <- sample(1:8, n, replace = TRUE)
  m <- Mode(x)
  if (!anyNA(m)) {
    add("o", c(0, n, x, 0), length(m)); add("o", c(0, n, x, 1), sum(m)); add("o", c(0, n, x, 2), attr(m, "freq"))
  }
  y <- c(round(rnorm(n) * 4, 2), sample(c(-60, 45, 80), sample(0:2, 1), replace = TRUE))
  for (kind in 1:2) {
    o <- Outlier(y, method = c("boxplot", "hampel")[kind])
    add("o", c(kind, length(y), y, 0), length(o)); add("o", c(kind, length(y), y, 1), sum(o))
  }
}
emit("desctools_outlier", "DescTools", list(cases))
