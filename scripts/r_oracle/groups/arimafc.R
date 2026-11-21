# forecast::Arima with seasonal terms (exact Gardner Kalman likelihood), its forecasts, intervals and fitted values.
#   fn "arima": args (qid, p, d, q, P, D, Q, m, kind, method, lambda, n, y...)
#     kind 0 none, 1 include.mean, 2 include.drift; method 0 CSS-ML, 1 ML, 2 CSS; lambda 5 means none
#     qid 1 loglik 2 aic 3 aicc 4 bic 5 sigma2 10+i coef i (R's order: ar, ma, sar, sma, regressor)
#         100+i fitted[n+1-i] (ML fits) 200+h point forecast 300+h forecast standard error (no lambda)
#         400+h upper 80% 500+h lower 95%
suppressMessages(library(forecast))
cases <- list()
add <- function(args, want, rel = 1e-9, abs = 1e-11) cases[[length(cases) + 1]] <<- case("arima", args, want, rel = rel, abs = abs)
fitone <- function(y, m, o, so, kind, method, lambda) {
  yy <- ts(y, frequency = m)
  f <- Arima(yy, order = o, seasonal = list(order = so, period = m), include.mean = kind == 1, include.drift = kind == 2,
             method = c("CSS-ML", "ML", "CSS")[method + 1], lambda = if (lambda == 5) NULL else lambda)
  n <- length(y)
  base <- c(o[1], o[2], o[3], so[1], so[2], so[3], m, kind, method, lambda, n, y)
  # The log-likelihood and the criteria are flat at the optimum and agree to 1e-9. The coefficients (and what follows from
  # them) of a differenced model fitted by ML come from optim's BFGS stopping at reltol 1e-8 on the objective: the likelihood of a
  # model with a diffuse (kappa 1e6) differenced state is flat, so the parameters at the stop are only determined to about
  # sqrt(1e-8) and move with the last bits of libm's log and tanh, which R's UCRT and Neper's math do not share. The Kalman
  # filter, getQ0, the transform and the lm start (QR coefficient and standard error) are ported term by term; measured worst
  # 5.5e-6 relative, checked at 2e-5. R-side proof of the limit: R's own Arima(ML) on y4i (1,1,0)(0,1,1) moves its coefficients by
# 5.5e-6 relative when the data are scaled by 1 + k*2^-50 (k = 1..6), a perturbation of the last bits of the input, so no port can
# match R's coefficients tighter than that without bit-identical libm; y12f moves 6.4e-7, y12 4.7e-8. Everything else (no differencing, or CSS) agrees to 1e-9.
  tolp <- if (o[2] + so[2] > 0 && method != 2) 2e-5 else 1e-9
  one <- function(q, v) add(c(q, base), v, rel = if (q <= 4) 1e-9 else tolp)
  fc <- forecast(f, h = 6, level = c(80, 95))
  one(1, f$loglik); one(5, f$sigma2)
  if (method != 2) { one(2, f$aic); one(3, f$aicc); one(4, f$bic) }
  for (i in seq_along(f$coef)) one(10 + i, f$coef[i])
  if (method != 2) for (i in 1:3) one(100 + i, as.numeric(fitted(f))[n + 1 - i])
  for (h in 1:6) {
    one(200 + h, as.numeric(fc$mean)[h])
    if (lambda == 5) one(300 + h, (fc$upper[h, 1] - fc$mean[h]) / qnorm(0.9))
    one(400 + h, fc$upper[h, 1]); one(500 + h, fc$lower[h, 2])
  }
}
# a seasonal ARIMA series of length n: (1 - a B)(1 - A B^m) w = (1 + t B)(1 + T B^m) e, integrated d and D times, on a level base
gen <- function(n, m, a, t, A, T, d, D, base) {
  ar <- if (a != 0 || A != 0) { p <- convolve(c(1, -a), rev(c(1, rep(0, m - 1), -A)), type = "o"); -p[-1] } else numeric()
  ma <- if (t != 0 || T != 0) { p <- convolve(c(1, t), rev(c(1, rep(0, m - 1), T)), type = "o"); p[-1] } else numeric()
  w <- as.numeric(arima.sim(list(ar = ar, ma = ma), n + 40, sd = 3))
  x <- w
  if (D > 0) x <- diffinv(x, lag = m, differences = D)
  if (d > 0) x <- diffinv(x, lag = 1, differences = d)
  x <- tail(x, n)
  round(base + x - x[1], 3)
}
set.seed(20261201)
y4 <- gen(60, 4, 0.5, 0.3, 0.4, 0, 0, 0, 50)
y4i <- gen(60, 4, 0, 0.4, 0, 0.5, 1, 1, 600)
y4d <- gen(60, 4, 0.3, 0.3, 0, 0.4, 0, 1, 100)
y4e <- gen(64, 4, 0.2, 0.4, 0, 0.5, 0, 1, 120)
y12 <- gen(96, 12, 0, 0.4, 0, 0.5, 1, 1, 1500)
y12d <- gen(96, 12, 0.4, 0, 0, 0.5, 0, 1, 300)
y12f <- gen(120, 12, 0.3, 0.3, 0.3, 0.3, 1, 1, 800)
y7 <- gen(70, 7, 0.3, 0.2, 0.3, 0, 0, 0, 40)
y7i <- gen(70, 7, 0, 0.3, 0, 0.4, 1, 1, 200)
fitone(y4, 4, c(1, 0, 0), c(1, 0, 0), 1, 0, 5)
fitone(y4, 4, c(1, 0, 0), c(1, 0, 0), 1, 1, 5)
fitone(y4, 4, c(1, 0, 0), c(1, 0, 0), 1, 2, 5)
fitone(y4, 4, c(2, 0, 1), c(1, 0, 1), 1, 0, 5)
fitone(y4i, 4, c(0, 1, 1), c(0, 1, 1), 0, 0, 5)
fitone(y4i, 4, c(1, 1, 0), c(0, 1, 1), 0, 1, 5)
fitone(y4d, 4, c(0, 0, 1), c(0, 1, 1), 2, 0, 5)
fitone(y4e, 4, c(1, 0, 1), c(0, 1, 1), 2, 0, 5)
fitone(y12, 12, c(0, 1, 1), c(0, 1, 1), 0, 0, 5)
fitone(y12d, 12, c(1, 0, 0), c(0, 1, 1), 2, 1, 5)
fitone(y12f, 12, c(1, 1, 1), c(1, 1, 1), 0, 0, 5)
fitone(y12, 12, c(0, 1, 1), c(0, 1, 1), 0, 2, 5)
fitone(y7, 7, c(1, 0, 1), c(1, 0, 0), 1, 0, 5)
fitone(y7i, 7, c(0, 1, 1), c(0, 1, 1), 0, 2, 5)
fitone(y12, 12, c(0, 1, 1), c(0, 1, 1), 0, 0, 0)
fitone(y4, 4, c(1, 0, 0), c(1, 0, 0), 1, 0, 0.5)
fitone(y4i, 4, c(0, 1, 1), c(0, 1, 1), 0, 0, 0)
emit("arimafc", "forecast", list(cases))
