# forecast::ets: single-model fits and the ZZZ search.
#   fn "fit":  args (qid, e, t, s, damped, m, n, y...)  e 1 A 2 M; t, s 0 N 1 A 2 M
#     qid 1 loglik 2 aic 3 aicc 4 bic 5 sigma2 6 mse 7 amse 8 alpha 9 beta 10 gamma 11 phi
#         12+i initial state i; 100+i fitted[n-i+1]; 200+h point forecast h
#   fn "auto": args (qid, m, n, y...)  qid 1 model code (damped 1000 + e 100 + t 10 + s) 2 aicc 3 alpha 200+h forecast h
suppressMessages(library(forecast))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-11) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
code <- c(N = 0, A = 1, M = 2)
fitcases <- function(y, m, E, T, S, damped) {
  yy <- ts(y, frequency = m)
  f <- ets(yy, model = paste0(E, T, S), damped = if (T == "N") NULL else damped, restrict = FALSE)
  n <- length(y); fc <- as.numeric(forecast(f, h = 6)$mean)
  base <- c(if (E == "A") 1 else 2, code[[T]], code[[S]], as.numeric(damped && T != "N"), m, n, y)
  one <- function(q, v) add("fit", c(q, base), v)
  one(1, f$loglik); one(2, f$aic); one(3, f$aicc); one(4, f$bic); one(5, f$sigma2); one(6, f$mse); one(7, f$amse)
  one(8, f$par[["alpha"]])
  if (T != "N") one(9, f$par[["beta"]])
  if (S != "N") one(10, f$par[["gamma"]])
  if (damped && T != "N") one(11, f$par[["phi"]])
  for (i in seq_along(f$initstate)) one(11 + i, f$initstate[i])
  for (i in 1:3) one(100 + i, f$fitted[n + 1 - i])
  for (h in 1:6) one(200 + h, fc[h])
  if (T != "M" && S != "M") {
    up <- forecast(f, h = 6, level = 80)$upper[, 1]
    for (h in 1:6) one(300 + h, (up[h] - fc[h]) / qnorm(0.9))
  }
}
mk <- function(n, m, base, slope, amp, noise, mult) {
  t <- 1:n
  s <- if (m > 1) sin(2 * pi * t / m + runif(1, 0, 6)) else 0 * t
  if (mult) round((base + slope * t) * (1 + amp * s) * exp(rnorm(n, 0, noise)), 3)
  else round(base + slope * t + amp * base * s + rnorm(n, 0, noise * base), 3)
}
set.seed(20261121)
for (spec in list(c(40, 1), c(60, 1), c(35, 1), c(48, 4), c(72, 4), c(60, 12))) {
  n <- spec[1]; m <- spec[2]
  y <- mk(n, m, runif(1, 40, 200), runif(1, -0.2, 1.2), 0.15, 0.05, TRUE)
  mods <- if (m == 1) list(c("A","N","N"), c("M","N","N"), c("A","A","N"), c("M","A","N"), c("M","M","N"))
          else list(c("A","N","A"), c("A","A","A"), c("M","N","M"), c("M","A","M"), c("M","N","A"), c("M","M","M"))
  for (md in mods) {
    fitcases(y, m, md[1], md[2], md[3], FALSE)
    if (md[2] != "N" && m == 1) fitcases(y, m, md[1], md[2], md[3], TRUE)
  }
  if (m == 4) fitcases(y, m, "A", "A", "A", TRUE)
}
#   fn "autom": the same with allow.multiplicative.trend = TRUE (series that grow geometrically)
auto <- function(y, m, amt = FALSE) {
  f <- ets(ts(y, frequency = m), allow.multiplicative.trend = amt); n <- length(y)
  nm <- if (amt) "autom" else "auto"
  cm <- f$components
  cd <- code[[cm[2]]] * 10 + code[[cm[3]]] + 100 * (if (cm[1] == "A") 1 else 2) + 1000 * (cm[4] == "TRUE")
  fc <- as.numeric(forecast(f, h = 6)$mean)
  b <- c(m, n, y)
  add(nm, c(1, b), cd); add(nm, c(2, b), f$aicc); add(nm, c(3, b), f$par[["alpha"]])
  for (h in 1:6) add(nm, c(200 + h, b), fc[h])
}
set.seed(20261122)
for (spec in list(c(50, 1), c(80, 1), c(40, 1), c(60, 1), c(48, 4), c(64, 4), c(72, 12))) {
  n <- spec[1]; m <- spec[2]
  y <- mk(n, m, runif(1, 40, 200), runif(1, -0.3, 1.5), runif(1, 0.05, 0.3), 0.06, spec[1] %% 2 == 0)
  auto(y, m)
}
#   fn "theta": args (qid, m, n, y...)  qid 1..6 thetaf(y, h = 6)$mean[h]; 11..16 its forecast standard error (upper80 - mean) / qnorm(0.9)
theta <- function(y, m) {
  fc <- thetaf(ts(y, frequency = m), h = 6, level = c(80, 95)); b <- c(m, length(y), y)
  for (h in 1:6) {
    add("theta", c(h, b), as.numeric(fc$mean[h]))
    add("theta", c(10 + h, b), as.numeric(fc$upper[h, 1] - fc$mean[h]) / qnorm(0.9))
  }
}
set.seed(20261124)
for (spec in list(c(30, 1), c(60, 1), c(40, 4), c(72, 4), c(48, 12), c(100, 12), c(36, 4), c(80, 1))) {
  n <- spec[1]; m <- spec[2]
  theta(mk(n, m, runif(1, 40, 200), runif(1, -0.2, 1.5), runif(1, 0.05, 0.4), 0.05, TRUE), m)
}
set.seed(20261126)
for (spec in list(c(40, 1), c(50, 1), c(48, 4), c(60, 1))) {
  n <- spec[1]; m <- spec[2]
  g <- runif(1, 0.01, 0.04)
  y <- round(exp(log(runif(1, 20, 100)) + g * (1:n) + rnorm(n, 0, 0.03)) * (if (m > 1) 1 + 0.15 * sin(2 * pi * (1:n) / m) else 1), 3)
  auto(y, m, TRUE)
}
#   fn "theta2": args (qid, m, n, lambda, y...)  thetaf(y, h = 6, lambda): qid 99 fitted[1], 100+i fitted[n+1-i], 200+h mean,
#     400+h upper 80, 700+h lower 95 (lambda 5 means none)
theta2 <- function(y, m, lam) {
  n <- length(y)
  fc <- thetaf(ts(y, frequency = m), h = 6, level = c(80, 95), lambda = if (lam == 5) NULL else lam)
  b <- c(m, n, lam, y)
  a2 <- function(q, v) add("theta2", c(q, b), v)
  a2(99, as.numeric(fc$fitted)[1])
  for (i in 1:3) a2(100 + i, as.numeric(fc$fitted)[n + 1 - i])
  for (h in 1:6) { a2(200 + h, fc$mean[h]); a2(400 + h, fc$upper[h, 1]); a2(700 + h, fc$lower[h, 2]) }
}
set.seed(20261125)
for (spec in list(c(30, 1, 5), c(60, 1, 0), c(40, 4, 5), c(72, 4, 0.5), c(48, 12, 5), c(100, 12, 0), c(80, 1, 0.3), c(36, 4, 1))) {
  n <- spec[1]; m <- spec[2]
  theta2(mk(n, m, runif(1, 40, 200), runif(1, -0.2, 1.5), runif(1, 0.05, 0.4), 0.05, TRUE), m, spec[3])
}
emit("etsfit", "forecast", list(cases))
