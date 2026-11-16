# xts: first and last with period strings, and merge by index. Indices are UTC days (daily or coarser data).
#   fl: (kind 0 first 1 last, unit 0 years 1 quarters 2 months 3 weeks 4 days, k, n, idx..., x...) -> fn "stat:fl" six cases (0 length 1 sum 2 position-weighted sum 3 first 4 last 5 NA count) of the kept values
#   merge: (join 0 outer 1 inner 2 left 3 right, nx, ny, idx_x..., x..., idx_y..., y...)  fn "stat:mx" "stat:my" "stat:mi" six cases each
library(xts)
set.seed(20261116)
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-11, abs = 1e-12)
vec <- function(name, args, v) {
  ok <- !is.na(v); w <- seq_along(v)
  st <- c(length(v), sum(v[ok]), sum(w[ok] * v[ok]), if (length(v)) v[1] else 0, if (length(v)) v[length(v)] else 0, sum(!ok))
  for (j in 0:5) add(paste0("stat:", name), c(args, j), st[j + 1])
}
t0 <- as.numeric(as.Date("2019-11-15"))
dd <- function(days) .POSIXct(86400 * (t0 + days), tz = "UTC")
idxs <- list(0:89, cumsum(c(0, sample(c(1, 1, 2, 3, 7), 119, replace = TRUE))), 7 * (0:59), 30 * (0:47), cumsum(c(0, sample(c(1, 2, 5), 79, replace = TRUE))))
units <- c("years", "quarters", "months", "weeks", "days")
for (idx in idxs) {
  x <- round(rnorm(length(idx)), 3); xs <- xts(x, dd(idx)); n <- length(idx)
  for (u in 0:4) for (k in c(1, 2, 3, 5, -1, -2)) for (kind in 0:1) {
    if (u == 0 && abs(k) > 2) next
    r <- tryCatch(suppressWarnings(if (kind == 0) first(xs, paste(k, units[u + 1])) else last(xs, paste(k, units[u + 1]))), error = function(e) NULL)
    if (is.null(r)) next
    vec("fl", c(kind, u, k, n, t0 + idx, x), as.numeric(r))
  }
}
for (rep in 1:20) {
  ix <- sort(sample(0:60, sample(10:40, 1))); iy <- sort(sample(0:60, sample(10:40, 1)))
  x <- round(rnorm(length(ix)), 3); y <- round(rnorm(length(iy)), 3)
  for (jn in c("outer", "inner", "left", "right")) {
    m <- merge(xts(x, dd(ix)), xts(y, dd(iy)), join = jn)
    a <- c(match(jn, c("outer", "inner", "left", "right")) - 1, length(ix), length(iy), t0 + ix, x, t0 + iy, y)
    vec("mx", a, as.numeric(m[, 1])); vec("my", a, as.numeric(m[, 2])); vec("mi", a, as.numeric(index(m)) / 86400)
  }
}
#   pi: (mode 0 endof 1 startof 2 firstof 3 lastof 4 yearmon 5 yearqtr, on 0 years 1 quarters 2 months 3 weeks 4 days, n, secs...)  fn "stat:pi" the index of to.period (six cases)
modes <- c("endof", "startof", "firstof", "lastof", "yearmon", "yearqtr")
for (idx in idxs) {
  secs <- (t0 + idx) * 86400 + 37800; n <- length(idx); xs <- xts(round(rnorm(n), 3), .POSIXct(secs, tz = "UTC"))
  for (u in 0:4) for (md in c(0, 1, 3, 4, 5)) {
    r <- tryCatch(suppressWarnings(to.period(xs, units[u + 1], indexAt = modes[md + 1])), error = function(e) NULL)
    if (is.null(r)) next
    v <- if (md >= 4) as.numeric(zoo::as.yearmon(.POSIXct(as.numeric(.index(r)), tz = "UTC"))) else as.numeric(.index(r))
    if (md == 5) v <- as.numeric(zoo::as.yearqtr(.POSIXct(as.numeric(.index(r)), tz = "UTC")))
    vec("pi", c(md, u, n, secs), v)
  }
}
emit("xts2", "xts", list(cases))
