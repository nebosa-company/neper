# forecast::ets prediction intervals beyond class1 and class2 (class3 by recursion, the rest simulated), and ets with a Box-Cox lambda.
#   fn "int": args (qid, e, t, s, damped, m, n, seed, y...)  e 1 A 2 M; t, s 0 N 1 A 2 M; set.seed(seed) just before forecast(h = 6)
#     qid 200+h mean  401+h-1.. upper 80  601.. lower 80  501.. upper 95  701.. lower 95   (h = 1..6)
#     The class3 models (MNM, MAM, MAdM) are analytic (1e-9); the simulated ones use the same 5000 x 6 normal draws and the same
#     type-8 quantiles (1e-9 as well, the paths are the same arithmetic).
#   fn "lam": args (qid, m, n, lambda, y...)  ets(y, lambda = lambda): qid 1 model code (damped 1000 + e 100 + t 10 + s) 2 aicc 3 loglik
#     4 sigma2 5 alpha 100+i fitted[n+1-i] 200+h mean 401.. upper 80 701.. lower 95 (all back-transformed)
suppressMessages(library(forecast))
cases <- list()
code <- c(N = 0, A = 1, M = 2)
intcase <- function(y, m, E, T, S, damped, seed) {
  yy <- ts(y, frequency = m)
  f <- ets(yy, model = paste0(E, T, S), damped = if (T == "N") NULL else damped, restrict = FALSE)
  n <- length(y)
  set.seed(seed)
  fc <- forecast(f, h = 6, level = c(80, 95))
  base <- c(if (E == "A") 1 else 2, code[[T]], code[[S]], as.numeric(damped && T != "N"), m, n, seed, y)
  one <- function(q, v) cases[[length(cases) + 1]] <<- case("int", c(q, base), v, rel = 1e-9, abs = 1e-11)
  for (h in 1:6) {
    one(200 + h, fc$mean[h])
    one(400 + h, fc$upper[h, 1]); one(600 + h, fc$lower[h, 1])
    one(500 + h, fc$upper[h, 2]); one(700 + h, fc$lower[h, 2])
  }
}
mk <- function(n, m, base, slope, amp, noise) {
  t <- 1:n
  s <- if (m > 1) sin(2 * pi * t / m + runif(1, 0, 6)) else 0 * t
  round((base + slope * t) * (1 + amp * s) * exp(rnorm(n, 0, noise)), 3)
}
set.seed(20261204)
y4 <- mk(60, 4, 80, 0.8, 0.15, 0.04)
y12 <- mk(84, 12, 120, 0.6, 0.2, 0.03)
y1 <- mk(50, 1, 100, 1.0, 0, 0.04)
seed <- 100
for (md in list(c("M", "N", "M"), c("M", "A", "M"), c("M", "A", "M", TRUE))) {
  intcase(y4, 4, md[1], md[2], md[3], length(md) > 3, seed); seed <- seed + 1
  intcase(y12, 12, md[1], md[2], md[3], length(md) > 3, seed); seed <- seed + 1
}
for (md in list(c("M", "M", "N"), c("M", "M", "N", TRUE), c("A", "M", "N"), c("A", "M", "N", TRUE))) {
  intcase(y1, 1, md[1], md[2], md[3], length(md) > 3, seed); seed <- seed + 1
}
for (md in list(c("A", "N", "M"), c("A", "A", "M"), c("M", "M", "A"), c("M", "M", "M"), c("A", "A", "M", TRUE))) {
  intcase(y4, 4, md[1], md[2], md[3], length(md) > 3, seed); seed <- seed + 1
}
lamcase <- function(y, m, lam) {
  yy <- ts(y, frequency = m)
  f <- ets(yy, lambda = lam)
  n <- length(y); cm <- f$components
  cd <- code[[cm[2]]] * 10 + code[[cm[3]]] + 100 * (if (cm[1] == "A") 1 else 2) + 1000 * (cm[4] == "TRUE")
  fc <- forecast(f, h = 6, level = c(80, 95))
  base <- c(m, n, lam, y)
  one <- function(q, v) cases[[length(cases) + 1]] <<- case("lam", c(q, base), v, rel = 1e-9, abs = 1e-11)
  one(1, cd); one(2, f$aicc); one(3, f$loglik); one(4, f$sigma2); one(5, f$par[["alpha"]])
  for (i in 1:3) one(100 + i, as.numeric(f$fitted)[n + 1 - i])
  for (h in 1:6) { one(200 + h, fc$mean[h]); one(400 + h, fc$upper[h, 1]); one(700 + h, fc$lower[h, 2]) }
}
lamcase(y1, 1, 0); lamcase(y1, 1, 0.5); lamcase(y4, 4, 0); lamcase(y4, 4, 0.3); lamcase(y12, 12, 0); lamcase(y12, 12, 0.7)
lamcase(y4, 4, 1); lamcase(y1, 1, -0.2)
emit("etsfc", "forecast", list(cases))
