# urca: ur.pp, ur.ers (DF-GLS and P-test) and ur.za.
#   pp: (type 0 Z-alpha 1 Z-tau, model 0 constant 1 trend, lags -1 short -2 long or the lag, n, y...)  fn "pp" q 0 stat 1 cval 1% 2 5% 3 10% 4 lag
#   ers: (type 0 DF-GLS 1 P-test, model 0 constant 1 trend, lag.max, n, y...)                      fn "ers" q 0 stat 1..3 cvals 4 lag
#   za: (model 0 intercept 1 trend 2 both, lag, n, y...)                                          fn "za" q 0 stat 1 bpoint 2..4 cvals
suppressMessages(library(urca))
set.seed(20261118)
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-9)
series <- list(cumsum(rnorm(80)), cumsum(rnorm(120, 0.1)), arima.sim(list(ar = 0.6), 100) + 3, arima.sim(list(ar = c(0.5, -0.3)), 140),
  cumsum(rnorm(60)) + 0.05 * (1:60), round(cumsum(rnorm(220, 0.05)), 3), arima.sim(list(ar = 0.9), 70), cumsum(rnorm(45)), c(cumsum(rnorm(50)), cumsum(rnorm(50)) + 8))
series <- lapply(series, function(v) as.numeric(round(v, 4)))
for (y in series) {
  n <- length(y)
  for (ty in 0:1) for (mo in 0:1) for (lg in c(-1, -2, 2, 5)) {
    r <- tryCatch(suppressWarnings(ur.pp(y, type = c("Z-alpha", "Z-tau")[ty + 1], model = c("constant", "trend")[mo + 1], lags = if (lg == -2) "long" else "short", use.lag = if (lg >= 0) lg else NULL)), error = function(e) NULL)
    if (is.null(r)) next
    a <- c(ty, mo, lg, n, y)
    add("pp", c(a, 0), r@teststat); for (l in 1:3) add("pp", c(a, l), r@cval[1, l]); add("pp", c(a, 4), r@lag)
  }
  for (ty in 0:1) for (mo in 0:1) for (lm in c(0, 2, 4, 6)) {
    r <- tryCatch(suppressWarnings(ur.ers(y, type = c("DF-GLS", "P-test")[ty + 1], model = c("constant", "trend")[mo + 1], lag.max = lm)), error = function(e) NULL)
    if (is.null(r)) next
    a <- c(ty, mo, lm, n, y)
    add("ers", c(a, 0), r@teststat); for (l in 1:3) add("ers", c(a, l), r@cval[1, l]); add("ers", c(a, 4), r@lag)
  }
  for (mo in 0:2) for (lg in c(0, 1, 3)) {
    r <- tryCatch(suppressWarnings(ur.za(y, model = c("intercept", "trend", "both")[mo + 1], lag = lg)), error = function(e) NULL)
    if (is.null(r)) next
    a <- c(mo, lg, n, y)
    add("za", c(a, 0), r@teststat); add("za", c(a, 1), r@bpoint); for (l in 1:3) add("za", c(a, 1 + l), r@cval[l])
  }
}
emit("urca2", "urca", list(cases))
