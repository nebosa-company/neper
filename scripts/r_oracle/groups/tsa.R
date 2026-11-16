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
for (rep in 1:14) {
  n <- sample(30:120, 1); y <- round(rnorm(n) * (1 + 0.8 * (rep %% 2) * abs(sin(seq_len(n) / 5))), 4)
  gl <- sample(4:15, 1)
  ml <- McLeod.Li.test(y = y, gof.lag = gl, plot = FALSE)$p.values
  add("mcl", c(n, gl, y), sum(ml * seq_along(ml)))
}
emit("tsa", "TSA", list(cases))
