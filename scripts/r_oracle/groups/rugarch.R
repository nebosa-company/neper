# rugarch ugarchfit sGARCH(1,1), constant mean, normal: "garch" args (n, y[n], k) k 0 mu, 1 omega, 2 alpha1, 3 beta1, 4 the log-likelihood
suppressMessages(library(rugarch))
cases <- list()
set.seed(20271217)
for (rep in 1:8) {
  n <- sample(300:450, 1); om <- runif(1, 0.05, 0.3); al <- runif(1, 0.05, 0.15); be <- runif(1, 0.6, 0.85); mu <- runif(1, -0.1, 0.1)
  e <- rnorm(n); h <- numeric(n); y <- numeric(n); h[1] <- om / (1 - al - be); y[1] <- mu + sqrt(h[1]) * e[1]
  for (t in 2:n) { h[t] <- om + al * (y[t - 1] - mu)^2 + be * h[t - 1]; y[t] <- mu + sqrt(h[t]) * e[t] }
  spec <- ugarchspec(variance.model = list(model = "sGARCH", garchOrder = c(1, 1)), mean.model = list(armaOrder = c(0, 0), include.mean = TRUE), distribution.model = "norm")
  f <- tryCatch(ugarchfit(spec, y, solver = "hybrid"), error = function(e) NULL)
  if (is.null(f) || convergence(f) != 0) next
  cf <- coef(f); if (cf[["alpha1"]] < 0.03 || cf[["alpha1"]] + cf[["beta1"]] > 0.97) next
  v <- c(cf[["mu"]], cf[["omega"]], cf[["alpha1"]], cf[["beta1"]], likelihood(f))
  for (k in seq_along(v)) cases[[length(cases) + 1]] <- case("garch", c(n, y, k - 1), as.numeric(v[k]), rel = if (k == 5) 1e-6 else 1e-2, abs = if (k == 5) 1e-4 else 1e-3)
}
emit("rugarch", "rugarch", list(cases))
