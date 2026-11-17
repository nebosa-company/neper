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
# na_locf "locf" (option 0..2 remaining, +10 for nocb; index; n; series) and na_interpolation "interp" (0 linear 1 spline; index; n; series), each answered per position
for (rep in 1:30) {
  n <- sample(12:30, 1); x <- round(runif(n, 1, 10), 1); na <- sample(n, sample(2:6, 1)); if (rep %% 3 == 0) na <- c(na, 1); if (rep %% 4 == 0) na <- c(na, n)
  x[na] <- NA; if (sum(!is.na(x)) < 4) next
  for (nc in c(FALSE, TRUE)) for (rm in 0:2) { r <- suppressWarnings(na_locf(x, option = if (nc) "nocb" else "locf", na_remaining = c("rev", "keep", "mean")[rm + 1])); for (k in seq_len(n)) add("locf", c(rm + if (nc) 10 else 0, k - 1, n, enc(x)), r[k]) }
  for (op in 0:1) { r <- suppressWarnings(na_interpolation(x, option = c("linear", "spline")[op + 1])); for (k in seq_len(n)) add("interp", c(op, k - 1, n, enc(x)), r[k]) }
}
# maxgap with na_locf (0 locf, 1 nocb, na_remaining keep) and na_interpolation (2 linear, 3 spline): "maxgap" (option, index, n, series..., maxgap)
for (rep in 1:30) {
  n <- sample(14:30, 1); x <- round(runif(n, 1, 10), 1); na <- c(sample(n, sample(3:7, 1))); x[na] <- NA; x[c(3, 4, 5, 6)] <- NA; if (sum(!is.na(x)) < 4) next; mg <- sample(1:3, 1)
  for (op in 0:3) { r <- suppressWarnings(switch(op + 1, na_locf(x, "locf", "keep", maxgap = mg), na_locf(x, "nocb", "keep", maxgap = mg), na_interpolation(x, "linear", maxgap = mg), na_interpolation(x, "spline", maxgap = mg)))
    for (k in seq_len(n)) add("maxgap", c(op, k - 1, n, enc(x), mg), r[k]) }
}
# na_random "rnd" (seed, index, n, series..., lower or -999999, upper or -999999) and na_replace "repl" (0, index, n, series..., fill)
for (rep in 1:20) {
  n <- sample(12:30, 1); x <- round(runif(n, 1, 10), 1); na <- sample(n, sample(2:6, 1)); x[na] <- NA; sd <- sample(1:100000, 1)
  lo <- if (rep %% 2) NULL else 0.5; hi <- if (rep %% 2) NULL else 12
  set.seed(sd); r <- na_random(x, lower_bound = lo, upper_bound = hi); fl <- sample(c(0, -1, 7.5), 1); r2 <- na_replace(x, fill = fl)
  for (k in seq_len(n)) { add("rnd", c(sd, k - 1, n, enc(x), if (is.null(lo)) -999999 else lo, if (is.null(hi)) -999999 else hi), r[k]); add("repl", c(0, k - 1, n, enc(x), fl), r2[k]) }
}
emit("imputets", "imputeTS", list(cases))
