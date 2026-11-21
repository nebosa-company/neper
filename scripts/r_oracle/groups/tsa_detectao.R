# TSA::detectAO (fn "ao") and TSA::detectIO (fn "io") on an ARMA(1, 1) fit. Args: (n, robust, resid[n], phi, theta, sigma2, which): which 0 the number of outliers, 1 the sum of their
# positions in rev(lambda) (1 based), 2 the sum of their lambda values. The fitted pieces are passed in; the fit is arima(x, c(1, 0, 1)).
suppressMessages(library(TSA))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-11) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261241)
for (rep in 1:12) {
  n <- sample(80:150, 1)
  x <- as.numeric(arima.sim(list(ar = 0.5, ma = 0.3), n))
  k <- sample(seq_len(n), 2); x[k] <- x[k] + c(6, -5)
  fit <- arima(x, order = c(1, 0, 1))
  robust <- rep %% 2
  out <- capture.output(d <- detectAO(fit, robust = robust == 1))
  base <- c(n, robust, as.numeric(residuals(fit)), as.numeric(fit$mod$phi), as.numeric(fit$mod$theta), fit$sigma2)
  add("ao", c(base, 0), length(d$ind))
  add("ao", c(base, 1), sum(d$ind))
  add("ao", c(base, 2), sum(d$lambda2))
  io <- detectIO(fit, robust = robust == 1)
  add("io", c(base, 0), length(io$ind)); add("io", c(base, 1), sum(io$ind)); add("io", c(base, 2), sum(io$lambda1))
}
emit("tsa_detectao", "TSA", list(cases))
