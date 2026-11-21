# forecast::bats and forecast::tbats (fit, information criteria, states, fitted values, forecast limits).
#   fn "bt": args (qid, kind, bcm, trm, dpm, arma, adj, freq, nper, per..., n, y...)
#     kind 0 bats 1 tbats; bcm, trm, dpm the use.box.cox, use.trend, use.damped.trend (0 NULL, 1 FALSE, 2 TRUE); arma use.arma.errors; adj biasadj;
#     freq the ts frequency, per the explicit seasonal.periods (nper 0 means NULL)
#   qid 1 lambda 2 alpha 3 beta 4 damping 5 likelihood 6 AIC 7 variance 8 p 9 q 10 states 11 optim code 12 1 when a tbats model
#     100+i gamma (bats: gamma values; tbats: gamma one then gamma two) 200+i ar 300+i ma 400+i k.vector 500+i seed state
#     600+i fitted (i-th from the end) 700+i errors (i-th from the end) 800+i last state 1000+h mean 1100+h lower 80 1200+h upper 80 1300+h lower 95 1400+h upper 95
#   Nelder-Mead paths are the same arithmetic as R's except where R sums in long double, so the checks are 1e-8 relative with an absolute floor.
suppressMessages(library(forecast))
cases <- list()
mk <- function(n, m, base, slope, amp, noise) {
  t <- 1:n
  s <- if (m > 1) sin(2 * pi * t / m + runif(1, 0, 6)) else 0 * t
  round((base + slope * t) * (1 + amp * s) * exp(rnorm(n, 0, noise)), 3)
}
set.seed(20261121)
y1 <- mk(50, 1, 100, 1.0, 0, 0.04)
y4 <- mk(60, 4, 80, 0.8, 0.15, 0.04)
y12 <- mk(72, 12, 120, 0.6, 0.2, 0.03)
y7 <- mk(70, 7, 60, 0.3, 0.25, 0.05)
y24 <- mk(96, 24, 90, 0.4, 0.2, 0.03)
yms <- round(mk(96, 12, 100, 0.5, 0.2, 0.03) * (1 + 0.1 * sin(2 * pi * (1:96) / 4)), 3)
y69 <- round(mk(72, 6, 100, 0.5, 0.2, 0.03) * (1 + 0.08 * sin(2 * pi * (1:72) / 9)), 3)
yneg <- round(mk(60, 4, 10, 0.2, 0.5, 0.0) - 25 + rnorm(60, 0, 1.5), 3)
ymas <- round(cumsum(rnorm(80, 0.1, 1)) + 50 + as.numeric(arima.sim(list(ar = 0.6), 80)) * 2, 3)

# a series with moving-average errors on top of `base`, redrawn until the model chosen by `chk` carries ARMA errors
mkarma <- function(base, freq, per, kind, mod, scale) {
  n <- length(base)
  repeat {
    e <- as.numeric(arima.sim(mod, n))
    y <- round(base + scale * e, 3)
    args <- list(y = ts(y, frequency = freq), use.box.cox = FALSE, use.trend = FALSE, use.damped.trend = FALSE, use.parallel = FALSE)
    if (!is.null(per)) args$seasonal.periods <- per
    fit <- suppressWarnings(do.call(if (kind == 0) bats else tbats, args))
    if (length(fit$ar.coefficients) + length(fit$ma.coefficients) > 0) return(y)
  }
}

fitcase <- function(y, freq, per, kind, bcm = 0, trm = 0, dpm = 0, arma = TRUE, adj = FALSE) {
  tri <- function(m) if (m == 0) NULL else m == 2
  yy <- ts(y, frequency = freq)
  args <- list(y = yy, use.box.cox = tri(bcm), use.trend = tri(trm), use.damped.trend = tri(dpm), use.arma.errors = arma,
               biasadj = adj, use.parallel = FALSE)
  if (!is.null(per)) args$seasonal.periods <- per
  fit <- suppressWarnings(do.call(if (kind == 0) bats else tbats, args))
  fc <- forecast(fit, h = 8, level = c(80, 95))
  base <- c(kind, bcm, trm, dpm, as.numeric(arma), as.numeric(adj), freq, length(per), per, length(y), y)
  # (x^l - 1) / l at l ~ 5e-9 loses l-relative precision: R's pow and Neper's differ in the last bit, which becomes 1e-8 of the states
  tiny <- !is.null(fit$lambda) && fit$lambda < 1e-4
  one <- function(q, v, abs = if (tiny) 1e-6 else 1e-10, rel = if (tiny) 1e-6 else 1e-8) if (length(v) == 1 && is.finite(v)) cases[[length(cases) + 1]] <<- case("bt", c(q, base), v, rel = rel, abs = abs)
  if (!is.null(fit$lambda)) one(1, fit$lambda, abs = 1e-9)
  one(2, fit$alpha); if (!is.null(fit$beta)) { one(3, fit$beta); one(4, fit$damping.parameter) }
  one(5, fit$likelihood); one(6, fit$AIC); one(7, fit$variance)
  p <- length(fit$ar.coefficients); q <- length(fit$ma.coefficients)
  one(8, p); one(9, q); one(10, nrow(fit$seed.states)); if (!tiny) one(11, fit$optim.return.code); one(12, as.numeric(inherits(fit, "tbats")))
  gam <- if (!is.null(fit$gamma.values)) fit$gamma.values else c(fit$gamma.one.values, fit$gamma.two.values)
  for (i in seq_along(gam)) one(100 + i, gam[i])
  for (i in seq_len(p)) one(200 + i, fit$ar.coefficients[i])
  for (i in seq_len(q)) one(300 + i, fit$ma.coefficients[i])
  if (!is.null(fit$k.vector)) for (i in seq_along(fit$k.vector)) one(400 + i, fit$k.vector[i])
  sd <- as.numeric(fit$seed.states)
  for (i in seq_along(sd)) one(500 + i, sd[i])
  n <- length(y)
  for (i in 1:2) { one(600 + i, as.numeric(fit$fitted.values)[n + 1 - i]); one(700 + i, as.numeric(fit$errors)[n + 1 - i]) }
  xl <- fit$x[, ncol(fit$x)]
  for (i in seq_along(xl)) one(800 + i, xl[i])
  for (h in c(1, 4, 8)) one(1000 + h, fc$mean[h])
  for (h in c(1, 8)) {
    one(1100 + h, fc$lower[h, 1]); one(1200 + h, fc$upper[h, 1]); one(1300 + h, fc$lower[h, 2]); one(1400 + h, fc$upper[h, 2])
  }
  cat(sprintf("kind %d n %d per %s -> %s\n", kind, length(y), paste(per, collapse = ","), as.character(fit)))
  invisible(fit)
}
tt <- 1:80
yma <- mkarma(100 + 0.1 * tt, 1, NULL, 0, list(ma = 0.8), 6)
yma4 <- mkarma(100 + 0.1 * tt + 8 * sin(2 * pi * tt / 4), 4, 4, 0, list(ma = 0.8), 3)
tt <- 1:96
ymams <- mkarma(100 + 0.1 * tt + 8 * sin(2 * pi * tt / 4) + 5 * sin(2 * pi * tt / 12), 12, c(4, 12), 0, list(ma = 0.8), 3)
ymat <- mkarma(100 + 0.1 * tt + 8 * sin(2 * pi * tt / 6), 6, 6, 1, list(ma = 0.8), 3)
# ARMA errors
fitcase(yma, 1, NULL, 0, bcm = 1, trm = 1)
fitcase(yma4, 4, 4, 0, bcm = 1, trm = 1)
fitcase(ymams, 12, c(4, 12), 0, bcm = 1, trm = 1)
fitcase(ymat, 6, 6, 1, bcm = 1, trm = 1)
# full searches
fitcase(y1, 1, NULL, 0)
fitcase(y4, 4, 4, 0)
fitcase(y12, 12, 12, 0)
# one specification
fitcase(y4, 4, 4, 0, bcm = 1, trm = 2, dpm = 2, arma = FALSE)
fitcase(y4, 4, 4, 0, bcm = 2, trm = 1, dpm = 1, arma = FALSE)
fitcase(y12, 12, 12, 0, bcm = 2, trm = 2, dpm = 1, arma = TRUE)
fitcase(y69, 6, c(6, 9), 0, bcm = 2, trm = 1, dpm = 1, arma = FALSE)
fitcase(yms, 12, c(4, 12), 0, bcm = 1, trm = 2, dpm = 1, arma = TRUE)
fitcase(yneg, 4, 4, 0, bcm = 0, trm = 0, dpm = 0, arma = TRUE)
fitcase(ymas, 1, NULL, 0, bcm = 1, trm = 1, dpm = 1, arma = TRUE)
fitcase(y4, 4, 4, 0, bcm = 2, trm = 2, dpm = 1, arma = FALSE, adj = TRUE)
fitcase(y7, 7, 7, 0, bcm = 1, trm = 1, dpm = 1, arma = FALSE)
# tbats
fitcase(y4, 4, 4, 1)
fitcase(y7, 7, 7, 1, bcm = 1, trm = 2, dpm = 2)
fitcase(y12, 12, 12, 1, bcm = 2, trm = 1, dpm = 1)
fitcase(yms, 12, c(4, 12), 1, bcm = 1, trm = 1, dpm = 1)
fitcase(y24, 24, 24, 1, bcm = 1, trm = 1, dpm = 1)
fitcase(y1, 1, NULL, 1, bcm = 1, trm = 2, dpm = 1)
fitcase(y7, 7, 7, 1)
fitcase(y12, 12, 12, 1, bcm = 2, trm = 1, dpm = 1, adj = TRUE)
fitcase(yneg, 4, 4, 1, trm = 1)
y125 <- mk(75, 12.5, 100, 0.4, 0.2, 0.03)
fitcase(y125, 12, 12.5, 1, bcm = 1, trm = 1, dpm = 1)
fitcase(y24, 24, 24, 0, bcm = 1, trm = 2, dpm = 1, arma = FALSE)
emit("batsfit", "forecast", list(cases))
