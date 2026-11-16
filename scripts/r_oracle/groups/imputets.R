# imputeTS: na_ma and na_mean. NA is encoded as -999999 in the args.
#   args: (kind, k_or_option, n, series...)   fn "ma" (kind 0 simple, 1 linear, 2 exponential; k) -> the position-weighted sum of the result
#   fn "mean" (option 0 mean, 1 median, 2 mode, 3 geometric, 4 harmonic) -> the filled value; series is positive
suppressMessages(library(imputeTS))
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
enc <- function(x) ifelse(is.na(x), -999999, x)
set.seed(20261205)
for (rep in 1:30) {
  n <- sample(12:30, 1); x <- round(runif(n, 1, 10), 1)
  if (rep %% 3 == 0) x[sample(n, 3)] <- round(x[1], 1)
  na <- sample(n, sample(2:6, 1)); if (rep %% 5 == 0) na <- c(na, 1, n)
  x[na] <- NA; if (sum(!is.na(x)) < 3) next
  w <- c("simple", "linear", "exponential")
  for (kind in 0:2) {
    k <- sample(1:5, 1)
    r <- na_ma(x, k = k, weighting = w[kind + 1])
    add("ma", c(kind, k, n, enc(x)), sum(r * seq_len(n)))
  }
  for (opt in 0:4) {
    r <- na_mean(x, option = c("mean", "median", "mode", "geometric", "harmonic")[opt + 1])
    add("mean", c(opt, 0, n, enc(x)), r[is.na(x)][1])
  }
}
emit("imputets", "imputeTS", list(cases))
