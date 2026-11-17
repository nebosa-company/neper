# coda: batchSE, summary.mcmc, gelman.diag(transform = TRUE) and effectiveSize of several chains.
#   "bse": (n, x, batch)   "sm_mean" "sm_sd" "sm_nse" "sm_tse": (n, x)   "sm_q": (n, x, prob) the summary.mcmc quantile
#   "gtp" "gtu": gelman.diag(transform = TRUE) point and upper psrf: (nchain, niter, chains row-major, confidence)
#   "ess_multi": effectiveSize of an mcmc.list, the sum over chains: (nchain, niter, chains row-major)
suppressMessages(library(coda))
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261215)
for (rep in 1:20) {
  n <- sample(c(120, 250, 500, 1050), 1); x <- as.vector(arima.sim(list(ar = runif(1, 0, 0.9)), n)) + 1
  bs <- sample(c(10, 25, 50, 100), 1); add("bse", c(n, x, bs), unname(batchSE(mcmc(cbind(x, rnorm(n))), batchSize = bs)[1]))
  s <- summary(mcmc(x)); a <- c(n, x)
  add("sm_mean", a, s$statistics[1]); add("sm_sd", a, s$statistics[2]); add("sm_nse", a, s$statistics[3]); add("sm_tse", a, s$statistics[4])
  pr <- sample(c(0.025, 0.25, 0.5, 0.75, 0.975), 1); add("sm_q", c(a, pr), quantile(x, pr))
}
for (rep in 1:20) {
  nc <- sample(2:4, 1); ni <- sample(c(100, 200, 400), 1); phi <- runif(1, 0, 0.8)
  pos <- rep %% 3
  ch <- lapply(seq_len(nc), function(k) mcmc({ z <- as.vector(arima.sim(list(ar = phi), ni)) + rnorm(1, 0, 0.4 * (rep %% 2)); if (pos == 0) exp(z / 2) else if (pos == 1) plogis(z) else z }))
  cm <- do.call(rbind, lapply(ch, as.vector)); a <- c(nc, ni, as.vector(t(cm)))
  g <- gelman.diag(mcmc.list(ch), transform = TRUE, confidence = 0.95); add("gtp", c(a, 0.95), g$psrf[1, 1]); add("gtu", c(a, 0.95), g$psrf[1, 2])
  add("ess_multi", a, sum(sapply(ch, effectiveSize)))
}
emit("coda3", "coda", list(cases))
