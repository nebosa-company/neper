# coda: heidel.diag, the multivariate gelman.diag psrf, pcramer, autocorr and crosscorr of a matrix of draws.
#   "hw_stest" "hw_start" "hw_p" "hw_htest" "hw_mean" "hw_half": args (n, x[n], eps, pvalue)
#   "mpsrf": args (nchain, niter, nvar, draws chain-major then row-major [nchain * niter * nvar])
#   "psrf_odd" / "psrf_oddu": gelman.diag point and upper psrf for an odd or even niter: args (nchain, niter, chains row-major, confidence)
#   "pc": args (q)
#   "ac" / "cc": args (n, nvar, draws row-major [n * nvar], u, v, lag) autocorr()[lag, u, v] and crosscorr()[u, v] (zero-based)
suppressMessages(library(coda))
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261210)
for (q in c(0.02, 0.05, 0.1, 0.2, 0.3, 0.5, 0.7, 1, 1.5, 2, 3, 5, 8)) add("pc", q, coda:::pcramer(q))
for (rep in 1:24) {
  n <- sample(c(60, 100, 150, 201, 300), 1); phi <- runif(1, 0, 0.9)
  burn <- if (rep %% 2 == 0) 4 * exp(-seq_len(n) / (n / 8)) else 0
  drift <- if (rep %% 6 == 0) 0.02 * seq_len(n) else 0
  x <- as.vector(arima.sim(list(ar = phi), n)) + burn + drift + (if (rep %% 3 == 0) 2 else 0.5)
  eps <- sample(c(0.1, 0.05), 1); pv <- sample(c(0.05, 0.1), 1)
  h <- heidel.diag(mcmc(x), eps = eps, pvalue = pv); a <- c(n, x, eps, pv)
  add("hw_stest", a, h[1, 1]); add("hw_start", a, h[1, 2]); add("hw_p", a, h[1, 3]); add("hw_htest", a, h[1, 4]); add("hw_mean", a, h[1, 5]); add("hw_half", a, h[1, 6])
}
for (rep in 1:14) {
  nc <- sample(2:4, 1); ni <- sample(c(40, 61, 100, 120), 1); nv <- sample(2:4, 1); phi <- runif(1, 0, 0.8)
  ch <- lapply(seq_len(nc), function(k) mcmc(sapply(seq_len(nv), function(v) as.vector(arima.sim(list(ar = phi), ni)) + rnorm(1, 0, 0.3 * (rep %% 3)) + 0.5 * v * rnorm(ni) )))
  g <- gelman.diag(mcmc.list(ch), multivariate = TRUE)
  add("mpsrf", c(nc, ni, nv, unlist(lapply(ch, function(m) as.vector(t(m))))), g$mpsrf)
}
for (rep in 1:10) {
  nc <- sample(2:4, 1); ni <- sample(c(61, 101, 201, 99), 1); phi <- runif(1, 0, 0.8)
  ch <- lapply(seq_len(nc), function(k) mcmc(as.vector(arima.sim(list(ar = phi), ni)) + rnorm(1, 0, 0.3 * (rep %% 3))))
  g <- gelman.diag(mcmc.list(ch), confidence = 0.9); cm <- do.call(rbind, lapply(ch, as.vector)); a <- c(nc, ni, as.vector(t(cm)), 0.9)
  add("psrf_odd", a, g$psrf[1, 1]); add("psrf_oddu", a, g$psrf[1, 2])
}
for (rep in 1:8) {
  n <- sample(c(80, 200, 300), 1); nv <- sample(2:3, 1)
  m <- sapply(seq_len(nv), function(v) as.vector(arima.sim(list(ar = runif(1, 0, 0.8)), n))); m[, nv] <- m[, nv] + 0.6 * m[, 1]
  ac <- autocorr(mcmc(m), lags = c(0, 1, 2, 5, 10)); cc <- crosscorr(mcmc(m)); a <- c(n, nv, as.vector(t(m)))
  u <- sample(0:(nv - 1), 1); v <- sample(0:(nv - 1), 1); li <- sample(1:5, 1)
  add("ac", c(a, u, v, c(0, 1, 2, 5, 10)[li]), ac[li, u + 1, v + 1]); add("cc", c(a, u, v, 0), cc[u + 1, v + 1])
}
emit("coda2", "coda", list(cases))
