# TSA: the periodogram.
#   args: (n, y...)   fn "pgram": the sum of spec_j * j over the frequencies j / n
suppressMessages(library(TSA))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261221)
for (rep in 1:20) {
  n <- sample(8:60, 1); y <- round(cumsum(rnorm(n)) + sin(seq_len(n)), 4)
  p <- periodogram(ts(y), plot = FALSE)
  add("pgram", c(n, y), sum(p$spec * seq_along(p$spec)))
}
emit("tsa", "TSA", list(cases))
