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
# geweke.diag z ("gz": (n, x, frac1, frac2)) and gelman.diag psrf ("gp" point, "gu" upper: (nchain, niter, chains row-major, confidence))
for (rep in 1:20) {
  n <- sample(c(100, 300, 1000), 1); phi <- runif(1, -0.3, 0.9); x <- as.vector(arima.sim(list(ar = phi), n)) + 0.003 * seq_len(n) * (rep %% 2)
  f1 <- sample(c(0.1, 0.2), 1); f2 <- sample(c(0.5, 0.4), 1); add("gz", c(n, x, f1, f2), as.numeric(geweke.diag(mcmc(x), frac1 = f1, frac2 = f2)$z))
  nc <- sample(2:5, 1); ni <- sample(c(100, 200, 400), 1); ch <- lapply(seq_len(nc), function(k) mcmc(as.vector(arima.sim(list(ar = phi), ni)) + rnorm(1, 0, 0.5 * (rep %% 3))))
  g <- gelman.diag(mcmc.list(ch), confidence = 0.95); cm <- do.call(rbind, lapply(ch, as.vector)); a <- c(nc, ni, as.vector(t(cm)), 0.95)
  add("gp", a, g$psrf[1, 1]); add("gu", a, g$psrf[1, 2])
}
for (rep in 1:20) { n <- sample(c(50, 200, 1000), 1); x <- if (rep %% 2) rgamma(n, 2) else rnorm(n); pr <- sample(c(0.8, 0.9, 0.95), 1); h <- HPDinterval(mcmc(x), prob = pr); add("hl", c(n, x, pr), h[1, 1]); add("hu", c(n, x, pr), h[1, 2]) }
emit("coda", "coda", list(cases))
