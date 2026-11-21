# forecast: BoxCox, InvBoxCox, BoxCox.lambda(method = "loglik") on a plain numeric series.
#   "bc" (x, lambda) ; "ibc" (x, lambda) ; "lam" (n, x[n], lower, upper)
suppressMessages(library(forecast))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-10, abs = 1e-12)
for (lam in c(-1, -0.5, -0.1, 0, 0.3, 0.5, 1, 2)) for (x in c(0.01, 0.5, 1, 2.5, 10, 100)) {
  add("bc", c(x, lam), as.numeric(BoxCox(x, lam)))
  add("ibc", c(x, lam), as.numeric(suppressWarnings(InvBoxCox(BoxCox(x, lam), lam))))
}
for (x in c(-2, -0.5, 0, 0.5, 2)) for (lam in c(0.5, 1, 2)) add("bc", c(x, lam), as.numeric(BoxCox(x, lam)))
set.seed(20261116)
for (rep in 1:30) {
  n <- sample(8:60, 1); x <- round(exp(rnorm(n, 2, runif(1, 0.1, 1.2))) + runif(1, 0, 5), 3)
  add("lam", c(n, x, -1, 2), BoxCox.lambda(x, method = "loglik", lower = -1, upper = 2))
  add("lam", c(n, x, -0.5, 1), BoxCox.lambda(x, method = "loglik", lower = -0.5, upper = 1))
}
#   "guer" (freq, n, x[n], lower, upper): BoxCox.lambda(ts(x, frequency = freq), method = "guerrero", lower, upper)
#   "cro" (type 0 croston 1 sba 2 sbj, alpha, n, y[n], pos): fitted[pos + 1] (pos = n: the forecast level)
set.seed(20261123)
for (rep in 1:30) {
  fr <- c(1, 4, 12, 7)[1 + rep %% 4]; n <- sample((3 * fr + 4):(8 * fr + 20), 1)
  x <- round(exp(rnorm(n, 3, runif(1, 0.1, 0.8))) * (1 + 0.3 * sin(2 * pi * seq_len(n) / max(fr, 3))) + runif(1, 0, 5), 3)
  for (lu in list(c(-1, 2), c(-0.5, 1.5), c(0, 1)))
    add("guer", c(fr, n, x, lu), BoxCox.lambda(ts(x, frequency = fr), method = "guerrero", lower = lu[1], upper = lu[2]))
}
for (rep in 1:24) {
  n <- sample(12:60, 1); y <- ifelse(runif(n) < runif(1, 0.3, 0.7), 0, round(runif(n, 1, 20), 2))
  if (sum(y != 0) < 3) y[c(2, 5, 9)] <- c(3, 4.5, 2)
  alpha <- c(0.1, 0.25, 0.5, 0.9)[1 + rep %% 4]; ty <- (rep %/% 4) %% 3
  fc <- croston(ts(y), h = 3, alpha = alpha, type = c("croston", "sba", "sbj")[ty + 1])
  for (pos in c(1, 2, n %/% 2, n - 1)) add("cro", c(ty, alpha, n, y, pos), fc$fitted[pos + 1])
  add("cro", c(ty, alpha, n, y, n), as.numeric(fc$mean[1]))
}
emit("fcast", "forecast", list(cases))
