# rugarch ugarchfit sGARCH(1,1), constant mean, normal: "garch" args (n, y[n], k) k 0 mu, 1 omega, 2 alpha1, 3 beta1, 4 the log-likelihood
suppressMessages(library(rugarch))
cases <- list()
set.seed(20271217)
for (rep in 1:5) {
  n <- sample(250:320, 1); om <- runif(1, 0.05, 0.3); al <- runif(1, 0.05, 0.15); be <- runif(1, 0.6, 0.85); mu <- runif(1, -0.1, 0.1)
  e <- rnorm(n); h <- numeric(n); y <- numeric(n); h[1] <- om / (1 - al - be); y[1] <- mu + sqrt(h[1]) * e[1]
  for (t in 2:n) { h[t] <- om + al * (y[t - 1] - mu)^2 + be * h[t - 1]; y[t] <- mu + sqrt(h[t]) * e[t] }
  spec <- ugarchspec(variance.model = list(model = "sGARCH", garchOrder = c(1, 1)), mean.model = list(armaOrder = c(0, 0), include.mean = TRUE), distribution.model = "norm")
  f <- tryCatch(ugarchfit(spec, y, solver = "hybrid"), error = function(e) NULL)
  if (is.null(f) || convergence(f) != 0) next
  cf <- coef(f); if (cf[["alpha1"]] < 0.03 || cf[["alpha1"]] + cf[["beta1"]] > 0.97) next
  v <- c(cf[["mu"]], cf[["omega"]], cf[["alpha1"]], cf[["beta1"]], likelihood(f))
  for (k in seq_along(v)) cases[[length(cases) + 1]] <- case("garch", c(n, y, k - 1), as.numeric(v[k]), rel = if (k == 5) 1e-6 else 1e-2, abs = if (k == 5) 1e-4 else 1e-3)
}
# gjrGARCH(1,1), constant mean, normal: "gjr" args (n, y[n], k) k 0 mu, 1 omega, 2 alpha1, 3 beta1, 4 gamma1, 5 the log-likelihood
for (rep in 1:5) {
  n <- sample(250:320, 1); om <- runif(1, 0.05, 0.3); al <- runif(1, 0.02, 0.08); ga <- runif(1, 0.05, 0.2); be <- runif(1, 0.55, 0.8); mu <- runif(1, -0.1, 0.1)
  e <- rnorm(n); h <- numeric(n); y <- numeric(n); h[1] <- om / (1 - al - be - ga / 2); y[1] <- mu + sqrt(h[1]) * e[1]
  for (t in 2:n) { r1 <- y[t - 1] - mu; h[t] <- om + (al + ga * (r1 < 0)) * r1^2 + be * h[t - 1]; y[t] <- mu + sqrt(h[t]) * e[t] }
  spec <- ugarchspec(variance.model = list(model = "gjrGARCH", garchOrder = c(1, 1)), mean.model = list(armaOrder = c(0, 0), include.mean = TRUE), distribution.model = "norm")
  f <- tryCatch(ugarchfit(spec, y, solver = "hybrid"), error = function(e) NULL)
  if (is.null(f) || convergence(f) != 0) next
  cf <- coef(f); if (cf[["alpha1"]] < 0.02 || cf[["alpha1"]] + cf[["beta1"]] + cf[["gamma1"]] / 2 > 0.97) next
  v <- c(cf[["mu"]], cf[["omega"]], cf[["alpha1"]], cf[["beta1"]], cf[["gamma1"]], likelihood(f))
  for (k in seq_along(v)) cases[[length(cases) + 1]] <- case("gjr", c(n, y, k - 1), as.numeric(v[k]), rel = if (k == 6) 1e-6 else 2e-2, abs = if (k == 6) 1e-4 else 2e-3)
}
# sGARCH(1,1), constant mean, standardised Student t: "gart" args (n, y[n], k) k 0 mu, 1 omega, 2 alpha1, 3 beta1, 4 shape, 5 the log-likelihood
for (rep in 1:5) {
  n <- sample(250:320, 1); om <- runif(1, 0.05, 0.3); al <- runif(1, 0.06, 0.15); be <- runif(1, 0.6, 0.8); mu <- runif(1, -0.1, 0.1); nu <- runif(1, 4, 9)
  e <- rt(n, nu) / sqrt(nu / (nu - 2)); h <- numeric(n); y <- numeric(n); h[1] <- om / (1 - al - be); y[1] <- mu + sqrt(h[1]) * e[1]
  for (t in 2:n) { h[t] <- om + al * (y[t - 1] - mu)^2 + be * h[t - 1]; y[t] <- mu + sqrt(h[t]) * e[t] }
  spec <- ugarchspec(variance.model = list(model = "sGARCH", garchOrder = c(1, 1)), mean.model = list(armaOrder = c(0, 0), include.mean = TRUE), distribution.model = "std")
  f <- tryCatch(ugarchfit(spec, y, solver = "hybrid"), error = function(e) NULL)
  if (is.null(f) || convergence(f) != 0) next
  cf <- coef(f); if (cf[["alpha1"]] < 0.03 || cf[["alpha1"]] + cf[["beta1"]] > 0.97 || cf[["shape"]] > 40) next
  v <- c(cf[["mu"]], cf[["omega"]], cf[["alpha1"]], cf[["beta1"]], cf[["shape"]], likelihood(f))
  for (k in seq_along(v)) cases[[length(cases) + 1]] <- case("gart", c(n, y, k - 1), as.numeric(v[k]), rel = if (k == 6) 1e-6 else 3e-2, abs = if (k == 6) 1e-4 else 5e-3)
}
# eGARCH(1,1), constant mean, normal: "egar" args (n, y[n], k) k 0 mu, 1 omega, 2 alpha1, 3 beta1, 4 gamma1, 5 the log-likelihood
for (rep in 1:5) {
  n <- sample(250:320, 1); om <- runif(1, -0.3, -0.05); al <- runif(1, -0.1, 0.05); ga <- runif(1, 0.1, 0.3); be <- runif(1, 0.7, 0.93); mu <- runif(1, -0.1, 0.1); Ez <- sqrt(2 / pi)
  e <- rnorm(n); lh <- numeric(n); y <- numeric(n); lh[1] <- om / (1 - be); y[1] <- mu + exp(lh[1] / 2) * e[1]
  for (t in 2:n) { z <- e[t - 1]; lh[t] <- om + al * z + ga * (abs(z) - Ez) + be * lh[t - 1]; y[t] <- mu + exp(lh[t] / 2) * e[t] }
  spec <- ugarchspec(variance.model = list(model = "eGARCH", garchOrder = c(1, 1)), mean.model = list(armaOrder = c(0, 0), include.mean = TRUE), distribution.model = "norm")
  f <- tryCatch(ugarchfit(spec, y, solver = "hybrid"), error = function(e) NULL)
  if (is.null(f) || convergence(f) != 0) next
  cf <- coef(f); if (cf[["beta1"]] > 0.97 || cf[["beta1"]] < 0.3) next
  v <- c(cf[["mu"]], cf[["omega"]], cf[["alpha1"]], cf[["beta1"]], cf[["gamma1"]], likelihood(f))
  for (k in seq_along(v)) cases[[length(cases) + 1]] <- case("egarch", c(n, y, k - 1), as.numeric(v[k]), rel = if (k == 6) 1e-6 else 3e-2, abs = if (k == 6) 1e-4 else 5e-3)
}
# iGARCH(1,1), constant mean, normal: "igarch" args (n, y[n], k) k 0 mu, 1 omega, 2 alpha1, 3 beta1, 4 the log-likelihood
for (rep in 1:5) {
  n <- sample(250:320, 1); om <- runif(1, 0.01, 0.06); al <- runif(1, 0.06, 0.2); be <- 1 - al; mu <- runif(1, -0.1, 0.1)
  e <- rnorm(n); h <- numeric(n); y <- numeric(n); h[1] <- 1; y[1] <- mu + sqrt(h[1]) * e[1]
  for (t in 2:n) { h[t] <- om + al * (y[t - 1] - mu)^2 + be * h[t - 1]; y[t] <- mu + sqrt(h[t]) * e[t] }
  spec <- ugarchspec(variance.model = list(model = "iGARCH", garchOrder = c(1, 1)), mean.model = list(armaOrder = c(0, 0), include.mean = TRUE), distribution.model = "norm")
  f <- tryCatch(ugarchfit(spec, y, solver = "hybrid"), error = function(e) NULL)
  if (is.null(f) || convergence(f) != 0) next
  cf <- coef(f); if (cf[["alpha1"]] < 0.03 || cf[["alpha1"]] > 0.9) next
  v <- c(cf[["mu"]], cf[["omega"]], cf[["alpha1"]], cf[["beta1"]], likelihood(f))
  for (k in seq_along(v)) cases[[length(cases) + 1]] <- case("igarchm", c(n, y, k - 1), as.numeric(v[k]), rel = if (k == 5) 1e-6 else 3e-2, abs = if (k == 5) 1e-4 else 5e-3)
}
emit("rugarch", "rugarch", list(cases))
