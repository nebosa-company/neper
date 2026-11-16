# Writes the Stata test files of tests/data/haven (formats 117 and 118) with haven 2.5.
suppressMessages(library(haven))
set.seed(1); n <- 12
df <- data.frame(id = 1:n, xnorm = round(rnorm(n), 3), yval = c(NA, round(runif(n - 1) * 100)), str = c("a", "bb", NA, "dddd", letters[5:12]), stringsAsFactors = FALSE)
df$lev <- labelled(sample(1:3, n, TRUE), labels = c(low = 1, mid = 2, high = 3), label = "Level")
attr(df$xnorm, "label") <- "A normal"
df$flag <- c(TRUE, FALSE, rep(NA, 2), rep(TRUE, 8)); df$cnt <- as.integer(c(NA, 5:15))
for (v in c(13, 14, 15)) write_dta(df, sprintf("tests/data/haven/t%d.dta", v), version = v, label = "Test data")
