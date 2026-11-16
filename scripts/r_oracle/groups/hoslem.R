# ResourceSelection::hoslem.test(y, yhat, g): the statistic, df, p value and the tables.
#   args: (g, n, y[n], yhat[n], q)  fn "h" q 0 chisq 1 df 2 p; 3 + i observed y0 of group i; then y1, e0, e1 (group counts as many as the result has)
suppressMessages(library(ResourceSelection))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261116)
for (rep in 1:40) {
  n <- sample(60:300, 1); g <- sample(c(4, 5, 8, 10), 1)
  x <- rnorm(n); pr <- plogis(0.3 + 0.9 * x); y <- rbinom(n, 1, pr); yhat <- round(plogis(0.2 + 0.8 * x + rnorm(n, 0, 0.2)), 5)
  h <- tryCatch(suppressWarnings(hoslem.test(y, yhat, g = g)), error = function(e) NULL)
  if (is.null(h)) next
  a <- c(g, n, y, yhat); G <- nrow(h$observed)
  add("h", c(a, 0), h$statistic[[1]]); add("h", c(a, 1), h$parameter[[1]]); add("h", c(a, 2), h$p.value)
  for (i in seq_len(G)) { add("h", c(a, 3 + i - 1), h$observed[i, 1]); add("h", c(a, 3 + G + i - 1), h$observed[i, 2]); add("h", c(a, 3 + 2 * G + i - 1), h$expected[i, 1]); add("h", c(a, 3 + 3 * G + i - 1), h$expected[i, 2]) }
}
emit("hoslem", "ResourceSelection", list(cases))
