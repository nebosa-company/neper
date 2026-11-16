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
for (rep in 1:24) {
  n <- sample(1:6, 1); w <- runif(1, 0.05, 0.9); hi <- rep %% 2; rp <- runif(1, 0.2, 3)
  ch <- cheby1(n, rp, w, if (hi == 1) "high" else "low")
  add("c1b", c(hi, n, w, rp), sum(ch$b * seq_along(ch$b))); add("c1a", c(hi, n, w, rp), sum(ch$a * seq_along(ch$a)))
}
for (rep in 1:24) {
  n <- sample(2:6, 1); w <- runif(1, 0.1, 0.9); hi <- rep %% 2; rs <- runif(1, 20, 60)
  ch <- cheby2(n, rs, w, if (hi == 1) "high" else "low")
  add("c2b", c(hi, n, w, rs), sum(ch$b * seq_along(ch$b))); add("c2a", c(hi, n, w, rs), sum(ch$a * seq_along(ch$a)))
}
for (rep in 1:20) {
  n <- sample(1:5, 1); w <- runif(1, 0.1, 0.8); hi <- rep %% 2
  bt <- butter(n, w, if (hi == 1) "high" else "low")
  g <- suppressWarnings(grpdelay(bt, n = 16))
  add("gd", c(hi, n, w), sum(g$gd[-1] * seq_along(g$gd[-1])))
}
for (rep in 1:20) {
  n <- sample(1:4, 1); w1 <- runif(1, 0.05, 0.5); w2 <- w1 + runif(1, 0.05, 0.4)
  bt <- butter(n, c(w1, w2), "pass")
  add("bpb", c(0, n, w1, w2), sum(bt$b * seq_along(bt$b))); add("bpa", c(0, n, w1, w2), sum(bt$a * seq_along(bt$a)))
}
for (rep in 1:24) {
  n <- sample(c(8, 16, 21, 30, 31, 41), 1); gridn <- sample(c(256, 512), 1); rn <- c(0, 2, gridn / 20)[rep %% 3 + 1]
  c1 <- sort(runif(2, 0.1, 0.9)); if (rep %% 2 == 0) { f <- c(0, c1[1], c1[1], c1[2], c1[2], 1); m <- c(0, 0, 1, 1, 0, 0) } else { f <- c(0, c1[1], c1[2], 1); m <- c(1, 1, 0.3, 0) }
  b <- fir2(n, f, m, gridn, rn, hamming(n + 1))
  add("fir2", c(n, gridn, rn, length(f), f, m), sum(as.numeric(b) * seq_along(b)))
}
for (rep in 1:24) {
  ty <- c("low", "high", "stop", "pass")[rep %% 4 + 1]; n <- sample(c(10, 20, 30, 40), 1)
  w <- if (ty %in% c("stop", "pass")) sort(runif(2, 0.1, 0.9)) else runif(1, 0.1, 0.9)
  b <- fir1(n, w, ty)
  add("fir1b", c(rep %% 4, n, length(w), w), sum(as.numeric(b) * seq_along(b)))
}
for (rep in 1:16) {
  len <- sample(60:200, 1); x <- round(cumsum(rnorm(len)), 4); q <- sample(2:5, 1); n <- sample(c(4, 6, 8), 1)
  d <- decimate(x, q, n)
  add("decim", c(n, q, len, x), sum(d * seq_along(d)))
  ph <- round(cumsum(rnorm(len, 0, 2.5)), 4); u <- unwrap(ph)
  add("unwrap", c(0, 0, len, ph), sum(u * seq_len(len)))
}
emit("signalpkg", "signal", list(cases))
