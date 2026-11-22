# actuar, fourth group: quantile, VaR and CTE of aggregateDist objects.
#   "ag" args (src, stat, p, params...): stat 0 quantile (step), 1 VaR with smooth = TRUE (ogive), 2 CTE
#   src 0 recursive: (kind 0 poisson 1 binomial 2 negative binomial 3 geometric, p1, p2, m, fx[m]); src 1 convolution: (m, fx[m], np, pn[np])
#   src 2 simulation of a Poisson-gamma compound (seed, n, lambda, shape, rate); src 3 normal (mean, variance); src 4 npower (mean, variance, skewness)
suppressMessages(library(actuar))
cases <- list()
add <- function(args, want, rel = 1e-9) if (is.finite(want)) cases[[length(cases) + 1]] <<- case("ag", args, want, rel = rel, abs = 1e-12)
# the last probability sits exactly on a cdf value (a tie in the inverse) unless tie is FALSE: convolve() goes through an FFT and the recursion through exp and log1p, whose last-bit differences make a tie unreliable there
probs <- function(F, tie = TRUE) {
  k <- knots(F); k <- k[length(k) %/% 2 + 1]
  c(0.1, 0.5, 0.75, 0.9, 0.95, 0.99, 0.995, if (tie) as.numeric(F(k)) else as.numeric(F(k)) * 1.0003)
}
setAll <- function(src, pre, F, ps) {
  for (p in ps) {
    add(c(src, 0, p, pre), as.numeric(quantile(F, p, names = FALSE)))
    add(c(src, 1, p, pre), as.numeric(VaR(F, p, smooth = TRUE, names = FALSE)))
    add(c(src, 2, p, pre), as.numeric(CTE(F, p, names = FALSE)))
  }
}
set.seed(20267100)
for (rep in 1:24) {
  kd <- rep %% 4; m <- sample(3:8, 1); fx <- c(runif(1, 0, 0.5), runif(m - 1)); fx[sample(2:m, 1)] <- 0; fx <- fx / sum(fx)
  F <- switch(kd + 1, { l <- runif(1, 0.5, 4); p1 <- l; p2 <- 0; aggregateDist("recursive", model.freq = "poisson", model.sev = fx, lambda = l, x.scale = 1) },
    { s <- sample(2:10, 1); pr <- runif(1, 0.1, 0.7); p1 <- s; p2 <- pr; aggregateDist("recursive", model.freq = "binomial", model.sev = fx, size = s, prob = pr, x.scale = 1) },
    { s <- runif(1, 0.5, 5); pr <- runif(1, 0.2, 0.8); p1 <- s; p2 <- pr; aggregateDist("recursive", model.freq = "negative binomial", model.sev = fx, size = s, prob = pr, x.scale = 1) },
    { pr <- runif(1, 0.2, 0.8); p1 <- pr; p2 <- 0; aggregateDist("recursive", model.freq = "geometric", model.sev = fx, prob = pr, x.scale = 1) })
  setAll(0, c(kd, p1, p2, m, fx), F, probs(F, FALSE))
}
for (rep in 1:14) {
  m <- sample(3:7, 1); fx <- c(runif(1, 0, 0.4), runif(m - 1)); fx <- fx / sum(fx); np <- sample(3:8, 1); pn <- runif(np); pn <- pn / sum(pn)
  F <- aggregateDist("convolution", model.freq = pn, model.sev = fx, x.scale = 1)
  setAll(1, c(m, fx, np, pn), F, probs(F, FALSE))
}
for (rep in 1:14) {
  sd <- sample(1:100000, 1); n <- sample(20:200, 1); lam <- runif(1, 0.5, 5); sh <- runif(1, 1, 4); rt <- runif(1, 0.3, 2)
  set.seed(sd)
  F <- aggregateDist("simulation", model.freq = eval(bquote(expression(data = rpois(.(lam))))), model.sev = eval(bquote(expression(data = rgamma(.(sh), .(rt))))), nb.simul = n)
  setAll(2, c(sd, n, lam, sh, rt), F, probs(F))
}
for (rep in 1:6) {
  mu <- runif(1, 5, 30); v <- runif(1, 4, 60); sk <- runif(1, 0.3, 1.5)
  Fn <- aggregateDist("normal", moments = c(mu, v)); Fp <- aggregateDist("npower", moments = c(mu, v, sk))
  for (p in c(0.6, 0.9, 0.95, 0.99)) {
    add(c(3, 0, p, mu, v), as.numeric(quantile(Fn, p, names = FALSE)), 1e-10); add(c(3, 2, p, mu, v), as.numeric(CTE(Fn, p, names = FALSE)), 1e-10)
    add(c(4, 0, p, mu, v, sk), as.numeric(quantile(Fp, p, names = FALSE)), 1e-10); add(c(4, 2, p, mu, v, sk), as.numeric(CTE(Fp, p, names = FALSE)), 1e-10)
  }
}
emit("actuar4", "actuar", list(cases))
