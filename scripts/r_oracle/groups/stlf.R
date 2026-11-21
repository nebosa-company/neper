# forecast::stlf(y, h = 2m) with the ets and arima methods, with and without a Box-Cox lambda.
#   fn "stlf": args (qid, method, m, n, lambda, y...)  method 0 ets 1 arima; lambda 5 means none
#     qid 100+i fitted[n+1-i]  200+h mean  300+h upper 80  400+h lower 80  500+h upper 95  600+h lower 95   (h = 1..2m)
# The arima method runs auto.arima on the seasonally adjusted series (an optim fit) (reltol 1e-8, parameters libm-sensitive as in arimafc.R): measured worst 5.8e-9, checked at 2e-8.
suppressMessages(library(forecast))
cases <- list()
one <- function(args, v, rel) cases[[length(cases) + 1]] <<- case("stlf", args, v, rel = rel, abs = 1e-11)
run <- function(y, m, method, lam) {
  n <- length(y)
  f <- stlf(ts(y, frequency = m), h = 2 * m, method = c("ets", "arima")[method + 1], lambda = if (lam == 5) NULL else lam)
  base <- c(method, m, n, lam, y)
  rel <- if (method == 1) 2e-8 else 1e-9
  for (i in 1:3) one(c(100 + i, base), f$fitted[n + 1 - i], rel)
  for (h in 1:(2 * m)) {
    one(c(200 + h, base), f$mean[h], rel)
    one(c(300 + h, base), f$upper[h, 1], rel); one(c(400 + h, base), f$lower[h, 1], rel)
    one(c(500 + h, base), f$upper[h, 2], rel); one(c(600 + h, base), f$lower[h, 2], rel)
  }
}
mk <- function(n, m, base, slope, amp, noise, mult) {
  t <- 1:n
  s <- sin(2 * pi * t / m + runif(1, 0, 6)) + 0.4 * cos(4 * pi * t / m + runif(1, 0, 6))
  if (mult) round((base + slope * t) * (1 + amp * s) * exp(rnorm(n, 0, noise)), 3)
  else round(base + slope * t + amp * base * s + rnorm(n, 0, noise * base), 3)
}
set.seed(20261203)
y4 <- mk(60, 4, 80, 0.8, 0.15, 0.04, FALSE)
y12 <- mk(96, 12, 120, 0.5, 0.2, 0.04, FALSE)
y7 <- mk(84, 7, 60, -0.1, 0.1, 0.05, FALSE)
y12m <- mk(120, 12, 150, 0.9, 0.25, 0.03, TRUE)
y4m <- mk(72, 4, 100, 1.1, 0.2, 0.03, TRUE)
for (spec in list(list(y4, 4), list(y12, 12), list(y7, 7), list(y12m, 12), list(y4m, 4))) run(spec[[1]], spec[[2]], 0, 5)
run(y12m, 12, 0, 0); run(y4m, 4, 0, 0.5); run(y12, 12, 0, 1)
run(y4, 4, 1, 5); run(y12, 12, 1, 5); run(y4m, 4, 1, 0)
emit("stlf", "forecast", list(cases))
