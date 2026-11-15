# xts on UTC time series: endpoints, to.period (OHLC), period.apply, align.time, periodicity, lag and diff.
# A vector answer is six cases (fn "stat:<name>"), the last argument being 0 length, 1 sum, 2 sum of position * value
# (positions from 1), 3 first, 4 last, 5 count of NA (the sums skip NA).
#   endpoints:   (on 0 years 1 quarters 2 months 3 weeks 4 days 5 hours 6 minutes 7 seconds, k, n, idx...)
#   ohlc_<o|h|l|c>: (on, k, n, idx..., x...)         the open, high, low, close of to.period over endpoints(on, k)
#   apply_<sum|mean|max|min>: (on, k, n, idx..., x...)  period.apply over endpoints(on, k)
#   align:       (by seconds, n, idx...)             align.time(x, by) index
#   period:      (n, idx...) -> periodicity frequency, then the scale code 0 secs 1 mins 2 hours 3 daily 4 weekly 5 monthly 6 quarterly 7 yearly
#   lag_diff:    (kind 0 lag 1 diff, k, n, x...)
library(xts)
set.seed(20261115)
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-11, abs = 1e-12)
vec <- function(name, args, v) {
  ok <- !is.na(v); w <- seq_along(v)
  st <- c(length(v), sum(v[ok]), sum(w[ok] * v[ok]), if (length(v)) v[1] else 0, if (length(v)) v[length(v)] else 0, sum(!ok))
  for (j in 0:5) add(paste0("stat:", name), c(args, j), st[j + 1])
}
t0 <- as.numeric(as.POSIXct("2019-11-15 08:30:00", tz = "UTC"))
mk <- function(secs) .POSIXct(t0 + secs, tz = "UTC")
idxs <- list(
  daily = 86400 * (0:44),
  hourly = 3600 * (0:59),
  minute = 60 * (0:89),
  irregular = cumsum(c(0, sample(c(3600, 86400, 86400 * 3, 86400 * 9, 86400 * 40), 39, replace = TRUE))),
  sparse = cumsum(c(0, round(runif(30, 1000, 4e6)))),
  secs = cumsum(c(0, sample(1:5, 70, replace = TRUE))))
ons <- c("years", "quarters", "months", "weeks", "days", "hours", "minutes", "seconds")
for (nm in names(idxs)) {
  s <- idxs[[nm]]; n <- length(s)
  x <- round(runif(n, 10, 20), 3)
  xt <- xts(x, mk(s))
  for (oi in seq_along(ons)) for (k in c(1, 3)) {
    ep <- tryCatch(endpoints(xt, ons[oi], k), error = function(e) NULL)
    if (is.null(ep)) next
    a <- c(oi - 1, k, n, t0 + s)
    vec("endpoints", a, ep)
    if (length(ep) > 2 || k == 1) {
      a2 <- c(oi - 1, k, n, t0 + s, x)
      seg <- lapply(seq_len(length(ep) - 1), function(i) x[(ep[i] + 1):ep[i + 1]])
      vec("ohlc_o", a2, sapply(seg, function(v) v[1])); vec("ohlc_h", a2, sapply(seg, max))
      vec("ohlc_l", a2, sapply(seg, min)); vec("ohlc_c", a2, sapply(seg, function(v) v[length(v)]))
      vec("apply_sum", a2, as.numeric(period.apply(xt, ep, sum)))
      vec("apply_mean", a2, as.numeric(period.apply(xt, ep, mean)))
      vec("apply_max", a2, as.numeric(period.apply(xt, ep, max)))
      vec("apply_min", a2, as.numeric(period.apply(xt, ep, min)))
    }
  }
  for (by in c(1, 5, 60, 300, 3600, 7200, 86400)) vec("align", c(by, n, t0 + s), as.numeric(.index(align.time(xt, by))) - t0)
  p <- suppressWarnings(periodicity(xt))
  sc <- match(p$scale, c("seconds", "minute", "hourly", "daily", "weekly", "monthly", "quarterly", "yearly")) - 1
  add("stat:period", c(n, t0 + s), p$frequency); add("stat:period_scale", c(n, t0 + s), sc)
  for (k in 1:3) for (kind in 0:1) {
    r <- if (kind == 0) as.numeric(lag(xt, k)) else as.numeric(diff(xt, lag = k))
    vec("lag_diff", c(kind, k, n, x), r)
  }
}
emit("xts", "xts", list(cases))
