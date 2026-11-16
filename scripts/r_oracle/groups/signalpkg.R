# signal: butter (low and high), fir1 and filter.
#   args: (kind, n, w, ...)   fn "b" "a" (the coefficient vectors weighted by position; kind 0 low, 1 high), "fir1" (weighted sum), "filt" (the filtered signal weighted by position; args (0, n, w, len, x...))
suppressMessages(library(signal))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-10)
set.seed(20261220)
for (rep in 1:30) {
  n <- sample(1:6, 1); w <- runif(1, 0.05, 0.9); hi <- rep %% 2
  bt <- butter(n, w, if (hi == 1) "high" else "low")
  add("b", c(hi, n, w), sum(bt$b * seq_along(bt$b))); add("a", c(hi, n, w), sum(bt$a * seq_along(bt$a)))

  len <- sample(10:40, 1); x <- round(rnorm(len), 4)
  y <- as.numeric(signal::filter(bt, x))
  add("filt", c(hi, n, w, len, x), sum(y * seq_len(len)))
}
for (rep in 1:20) {
  n <- sample(1:5, 1); w <- runif(1, 0.05, 0.9); hi <- rep %% 2
  bt <- butter(n, w, if (hi == 1) "high" else "low")
  len <- sample(10:40, 1); x <- round(rnorm(len), 4)
  ff <- as.numeric(filtfilt(bt$b, bt$a, x))
  add("ff", c(hi, n, w, len, x), sum(ff * seq_len(len)))
  fr <- freqz(bt$b, bt$a, c(0.1, 0.5, 1.2, 2.0, 3.0))
  add("fre", c(hi, n, w), sum(Re(fr$h) * 1:5)); add("fim", c(hi, n, w), sum(Im(fr$h) * 1:5))
}
for (rep in 1:20) {
  n <- sample(c(5, 7, 9, 11, 13, 15, 21), 1); p <- sample(1:min(5, n - 2), 1)
  sg <- sgolay(p, n); ce <- sg[(n + 1) / 2, ]
  add("sg", c(0, n, p), sum(ce * seq_along(ce)))
}
emit("signalpkg", "signal", list(cases))
