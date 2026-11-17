# coda, second half: heidel.diag, the multivariate gelman.diag psrf, crosscorr, multivariate autocorr and pcramer.
#   "hw_stest" "hw_start" "hw_p" "hw_htest" "hw_mean" "hw_half": (n, x, eps)
#   "mp" mpsrf and "mp_p"/"mp_u" psrf of variable 1: (nchain, niter, nvar, draws chain-major, row-major per chain)
#   "cc": (n, nvar, x row-major, u, v)   "ac": (n, nvar, x row-major, u, v, lag)   "pc": (q)
suppressMessages(library(coda))
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261301)
for (rep in 1:20) {
  n <- sample(c(40, 100, 105, 301), 1); phi <- runif(1, -0.3, 0.9)
  x <- as.vector(arima.sim(list(ar = phi), n)) + (if (rep %% 3 == 0) 0.01 * seq_len(n) * runif(1) else 0) + (if (rep %% 2) 5 else 0.5)
  eps <- sample(c(0.1, 0.05, 0.5), 1); a <- c(n, x, eps)
  h <- heidel.diag(mcmc(x), eps = eps)
  nm <- c("hw_stest", "hw_start", "hw_p", "hw_htest", "hw_mean", "hw_half")
  for (k in 1:6) add(nm[k], a, h[1, k])
}
for (rep in 1:20) {
  nc <- sample(2:3, 1); ni <- sample(c(60, 101, 200), 1); nv <- sample(2:3, 1)
  A <- matrix(rnorm(nv * nv), nv); mu <- rnorm(nv, 0, 0.3 * (rep %% 3))
  ch <- lapply(seq_len(nc), function(k) { z <- matrix(rnorm(ni * nv), ni); for (t in 2:ni) z[t, ] <- 0.5 * z[t - 1, ] + z[t, ]; mcmc(z %*% A + matrix(mu * k, ni, nv, byrow = TRUE)) })
  g <- gelman.diag(mcmc.list(ch), autoburnin = TRUE)
  a <- c(nc, ni, nv, unlist(lapply(ch, function(m) as.vector(t(m)))))
  add("mp", a, g$mpsrf); add("mp_p", a, g$psrf[1, 1]); add("mp_u", a, g$psrf[1, 2])
}
for (rep in 1:25) {
  n <- sample(c(30, 200), 1); nv <- sample(2:4, 1); z <- matrix(rnorm(n * nv), n); for (t in 2:n) z[t, ] <- 0.6 * z[t - 1, ] + z[t, ]
  z <- z %*% matrix(rnorm(nv * nv), nv); u <- sample(nv, 1); v <- sample(nv, 1); lag <- sample(0:7, 1)
  a <- c(n, nv, as.vector(t(z)), u - 1, v - 1)
  add("cc", a, crosscorr(mcmc(z))[u, v]); add("ac", c(a, lag), autocorr(mcmc(z), lags = lag)[1, u, v])
}
for (q in c(0.02, 0.05, 0.1, 0.2, 0.35, 0.5, 0.8, 1.2, 2, 3.5)) add("pc", q, coda:::pcramer(q))
emit("coda2", "coda", list(cases))
