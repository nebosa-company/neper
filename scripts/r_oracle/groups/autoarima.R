# forecast::auto.arima (stepwise and exhaustive), ndiffs (kpss, adf, pp), nsdiffs (seas, ocsb, ch), ocsb.test and uroot::ch.test.
#   fn "auto":    args (qid, stepwise, appr, test, stest, m, n, y...)  appr 0 default 1 FALSE 2 TRUE; test 0 kpss 1 adf 2 pp; stest 0 seas 1 ocsb 2 ch
#     qid 1 p 2 d 3 q 4 P 5 D 6 Q 7 constant (1 when an intercept or drift was fitted) 8 aicc 9 loglik 10 sigma2
#         20+i coef i, 200+h point forecast h, 300+h forecast standard error (upper 80 - mean) / qnorm(.9)
#   fn "ndiffs":  args (test, maxd, n, y...)      ndiffs(y, test, max.d = maxd)
#   fn "nsdiffs": args (stest, maxD, m, n, y...)  nsdiffs(ts(y, m), test, max.D = maxD)
#   fn "ocsb":    args (qid, m, n, y...)  ocsb.test(x, maxlag = 3, lag.method = "AIC"): qid 1 statistic 2 critical value 3 lag order
#   fn "ch":      args (qid, m, n, y...)  uroot::ch.test(x, type = "trig"): qid 1 joint statistic 2 joint p-value (response surface)
suppressMessages({ library(forecast); library(uroot) })
cases <- list()
tests <- c("kpss", "adf", "pp"); stests <- c("seas", "ocsb", "ch")
gen <- function(n, m, a, t, A, T, d, D, base, sd = 3) {
  ar <- if (a != 0 || A != 0) { p <- convolve(c(1, -a), rev(c(1, rep(0, max(m, 2) - 1), -A)), type = "o"); -p[-1] } else numeric()
  ma <- if (t != 0 || T != 0) { p <- convolve(c(1, t), rev(c(1, rep(0, max(m, 2) - 1), T)), type = "o"); p[-1] } else numeric()
  w <- as.numeric(arima.sim(list(ar = ar, ma = ma), n + 40, sd = sd))
  x <- w
  if (D > 0) x <- diffinv(x, lag = m, differences = D)
  if (d > 0) x <- diffinv(x, lag = 1, differences = d)
  x <- tail(x, n)
  round(base + x - x[1], 3)
}
set.seed(20261202)
nd <- list(
  gen(80, 1, 0.6, 0, 0, 0, 0, 0, 10), gen(100, 1, 0, 0, 0, 0, 1, 0, 50), gen(60, 1, 0, 0, 0, 0, 2, 0, 100),
  round(5 + 0.4 * (1:90) + rnorm(90, 0, 3), 3), gen(120, 1, 0.9, 0, 0, 0, 0, 0, 20),
  round(cumsum(rnorm(70, 0.5, 1)) + 10, 3), gen(50, 1, 0.3, 0.4, 0, 0, 1, 0, 80))
for (y in nd) for (ti in 0:2) {
  add <- function(md, v) cases[[length(cases) + 1]] <<- case("ndiffs", c(ti, md, length(y), y), v, rel = 0, abs = 0)
  add(2, ndiffs(y, test = tests[ti + 1], max.d = 2))
  add(1, ndiffs(y, test = tests[ti + 1], max.d = 1))
}
sd_series <- list(
  list(4, round(50 + 8 * sin(2 * pi * (1:80) / 4 + 1) + rnorm(80, 0, 2), 3)),
  list(4, gen(80, 4, 0, 0.3, 0, 0.4, 0, 1, 100)),
  list(12, round(100 + 15 * sin(2 * pi * (1:120) / 12) + 5 * cos(4 * pi * (1:120) / 12) + rnorm(120, 0, 3), 3)),
  list(12, gen(144, 12, 0.3, 0, 0, 0.4, 0, 1, 300)),
  list(7, round(40 + rnorm(70, 0, 3), 3)),
  list(4, gen(60, 4, 0.5, 0, 0.3, 0, 0, 0, 30)),
  list(12, gen(132, 12, 0, 0.3, 0, 0, 1, 1, 800)),
  list(6, round(60 + 5 * sin(2 * pi * (1:90) / 6) + rnorm(90, 0, 4), 3)))
for (s in sd_series) {
  m <- s[[1]]; y <- s[[2]]; n <- length(y); x <- ts(y, frequency = m)
  for (si in 0:2) {
    add <- function(md, v) cases[[length(cases) + 1]] <<- case("nsdiffs", c(si, md, m, n, y), v, rel = 0, abs = 0)
    add(1, nsdiffs(x, test = stests[si + 1], max.D = 1))
    add(2, nsdiffs(x, test = stests[si + 1], max.D = 2))
  }
  o <- ocsb.test(x, maxlag = 3, lag.method = "AIC")
  cases[[length(cases) + 1]] <- case("ocsb", c(1, m, n, y), o$statistics, rel = 1e-9, abs = 1e-11)
  cases[[length(cases) + 1]] <- case("ocsb", c(2, m, n, y), o$critical, rel = 1e-9, abs = 1e-11)
  cases[[length(cases) + 1]] <- case("ocsb", c(3, m, n, y), o$lag.order, rel = 0, abs = 0)
  ch <- ch.test(x, type = "trigonometric")
  js <- length(ch$statistics)
  cases[[length(cases) + 1]] <- case("ch", c(1, m, n, y), ch$statistics[js], rel = 1e-9, abs = 1e-11)
  cases[[length(cases) + 1]] <- case("ch", c(2, m, n, y), ch$pvalues["joint"], rel = 1e-8, abs = 1e-11)
}
# auto.arima. The criteria are flat at the optimum (1e-9); coefficients of a differenced model come from optim stopping at
# reltol 1e-8 on a flat diffuse-state likelihood (the parameters at the stop move with the last bits of libm, as in arimafc.R) and agree to
# 5e-6 relative (measured worst 1.2e-6); the criteria, orders and the closed-form branches agree to 1e-9 or exactly.
aa <- function(y, m, stepwise, appr, test = 0, stest = 0) {
  yy <- ts(y, frequency = m); n <- length(y)
  f <- auto.arima(yy, stepwise = stepwise, approximation = if (appr == 0) (n > 150 || m > 12) else appr == 2,
                  test = tests[test + 1], seasonal.test = stests[stest + 1])
  base <- c(stepwise, appr, test, stest, m, n, y)
  arma <- f$arma; dd <- arma[6] + arma[7]
  tolp <- if (dd > 0) 5e-6 else 1e-9
  one <- function(q, v, rel = tolp) cases[[length(cases) + 1]] <<- case("auto", c(q, base), v, rel = rel, abs = 1e-11)
  one(1, arma[1], 0); one(2, arma[6], 0); one(3, arma[2], 0); one(4, arma[3], 0); one(5, arma[7], 0); one(6, arma[4], 0)
  one(7, as.numeric(any(names(f$coef) %in% c("intercept", "drift"))), 0)
  one(8, f$aicc, 1e-9); one(9, f$loglik, 1e-9); one(10, f$sigma2)
  for (i in seq_along(f$coef)) one(20 + i, f$coef[i])
  fc <- forecast(f, h = 6, level = 80)
  for (h in 1:6) { one(200 + h, fc$mean[h]); one(300 + h, (fc$upper[h] - fc$mean[h]) / qnorm(0.9)) }
}
ar1 <- gen(60, 1, 0.6, 0.3, 0, 0, 0, 0, 20)
rw1 <- gen(70, 1, 0.4, 0, 0, 0, 1, 0, 100)
s4 <- gen(60, 4, 0.4, 0.2, 0.4, 0, 0, 0, 50)
s4i <- gen(64, 4, 0, 0.4, 0, 0.5, 1, 1, 600)
s12 <- gen(96, 12, 0.3, 0, 0, 0.5, 0, 1, 300)
aa(ar1, 1, TRUE, 0); aa(rw1, 1, TRUE, 0); aa(s4, 4, TRUE, 0); aa(s4i, 4, TRUE, 0); aa(s12, 12, TRUE, 0)
aa(rw1, 1, TRUE, 0, 1); aa(rw1, 1, TRUE, 0, 2); aa(s4, 4, TRUE, 0, 0, 1); aa(s4i, 4, TRUE, 0, 0, 2)
aa(ar1, 1, FALSE, 1); aa(rw1, 1, FALSE, 1); aa(s4, 4, FALSE, 1)
aa(gen(48, 4, 0.4, 0.3, 0.3, 0, 0, 0, 40), 4, FALSE, 1)
aa(ar1, 1, FALSE, 2); aa(gen(200, 1, 0.5, 0.3, 0, 0, 0, 0, 30), 1, TRUE, 0)
aa(gen(168, 12, 0.3, 0, 0, 0.5, 0, 1, 300), 12, TRUE, 0)
# the closed-form branches: a constant series, constant after one or two differences, constant after the seasonal difference (alone and with d = 1)
aa(rep(5, 30), 1, TRUE, 0)
aa(3 + 2 * (1:40), 1, TRUE, 0)
aa(1 + (1:40)^2, 1, TRUE, 0)
aa(rep(c(3, 7, 5, 9), 15) + 0.5 * (1:60), 4, TRUE, 0)
aa(rep(c(3, 7, 5, 9), 15) + 0.5 * (1:60) + 0.25 * (1:60)^2, 4, TRUE, 0)
emit("autoarima", "forecast", list(cases))
