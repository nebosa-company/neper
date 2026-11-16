# coda: effectiveSize, autocorr and spectrum0.ar of one chain.
#   args: (n, x[n], lag.max)   fn "ess" "ar_order" "ar_spec" "acf_sum" (sum of the acf at lags 0..lag.max weighted by lag + 1)
suppressMessages(library(coda))
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261201)
for (rep in 1:30) {
  n <- sample(c(50, 100, 400, 1000), 1); phi <- runif(1, -0.5, 0.95); x <- as.vector(arima.sim(list(ar = phi), n)) + if (rep %% 3 == 0) 0.002 * seq_len(n) else 0
  lm <- sample(c(5, 10, 20), 1); a <- c(n, x, lm)
  add("ess", a, as.numeric(effectiveSize(mcmc(x))))
  s0 <- spectrum0.ar(x); add("ar_order", a, s0$order); add("ar_spec", a, s0$spec)
  ac <- as.vector(acf(x, lag.max = lm, plot = FALSE)$acf); add("acf_sum", a, sum(ac * seq_along(ac)))
}
emit("coda", "coda", list(cases))
