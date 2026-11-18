# TSA's cumulative periodogram (stats::cpgram plots it; the values are the same expressions as its body, reproduced here).
# Args: (n, taper_percent, series[n], which): which 0 the number of frequencies, 1 the critical value, 2 the sum of the cumulative proportions,
# 3 the sum of index * cumulative proportion (1 based).
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261242)
cp_values <- function(ts, taper = 0.1) {
  x <- as.vector(ts); x <- x[!is.na(x)]
  x <- stats::spec.taper(scale(x, TRUE, FALSE), p = taper)
  y <- Mod(fft(x))^2 / length(x); y[1L] <- 0
  n <- length(x)
  x <- (0:(n / 2)) * 1 / n
  if (length(x) %% 2 == 0) { n <- length(x) - 1; y <- y[1L:n]; x <- x[1L:n] } else y <- y[seq_along(x)]
  mp <- length(x) - 1
  crit <- 1.358 / (sqrt(mp) + 0.12 + 0.11 / sqrt(mp))
  list(cum = cumsum(y) / sum(y), crit = crit)
}
for (rep in 1:12) {
  n <- sample(40:120, 1)
  s <- as.numeric(arima.sim(list(ar = 0.4), n)) + sin(2 * pi * (1:n) / sample(4:12, 1))
  r <- cp_values(s, 0.1)
  base <- c(n, 10, s)
  add("cp", c(base, 0), length(r$cum)); add("cp", c(base, 1), r$crit)
  add("cp", c(base, 2), sum(r$cum)); add("cp", c(base, 3), sum(seq_along(r$cum) * r$cum))
}
emit("tsa_cpgram", "TSA", list(cases))
