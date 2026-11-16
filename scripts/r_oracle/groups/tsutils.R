# tseries: bds.test and tsbootstrap.
#   bds: (m, eps, n, x[n], d) fn "bds" -> statistic for embedding dimension d (2..m) at eps
#   tsb: (seed, type 0 stationary 1 block, b, nb, stat 0 mean 1 median 2 sd 3 var, n, x[n], q) fn "tsb" q 0 sum 1 weighted sum of the nb statistics, 2 first 3 last
suppressMessages(library(tseries))
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-11)
set.seed(20261118)
for (rep in 1:30) {
  n <- sample(40:220, 1); x <- if (rep %% 3 == 0) as.numeric(arima.sim(list(ar = 0.5), n)) else if (rep %% 3 == 1) rnorm(n) else round(rexp(n), 3)
  m <- sample(3:6, 1); e <- seq(0.5 * sd(x), 2 * sd(x), length.out = 4)
  b <- bds.test(x, m = m, eps = e)
  for (k in seq_along(e)) for (d in 2:m) add("bds", c(m, e[k], n, x, d), b$statistic[d - 1, k])
}
fs <- list(mean, median, sd, var)
for (rep in 1:40) {
  n <- sample(30:150, 1); x <- round(cumsum(rnorm(n)), 3); ty <- sample(0:1, 1); nb <- sample(3:30, 1); st <- sample(0:3, 1)
  b <- if (ty == 0) runif(1, 1.5, n / 3) else sample(2:max(2, n %/% 4), 1)
  seed <- sample(1e6, 1); set.seed(seed)
  r <- tryCatch(tsbootstrap(x, nb = nb, statistic = fs[[st + 1]], b = b, type = c("stationary", "block")[ty + 1]), error = function(e) NULL)
  if (is.null(r)) next
  v <- as.vector(r$statistic); a <- c(seed, ty, b, nb, st, n, x)
  add("tsb", c(a, 0), sum(v)); add("tsb", c(a, 1), sum(seq_along(v) * v)); add("tsb", c(a, 2), v[1]); add("tsb", c(a, 3), v[length(v)])
}
# terasvirta.test and white.test: (kind 0 terasvirta 1 white, seed, n, nin, type 0 Chisq 1 F, scale, qstar, q, range, x col-major[n*nin], y[n], what) fn "nn" what 0 statistic 1 df1 2 df2
for (rep in 1:60) {
  n <- sample(50:300, 1); nin <- sample(1:3, 1); kind <- rep %% 2; ty <- sample(0:1, 1); sc <- sample(0:1, 1)
  x <- matrix(round(rnorm(n * nin), 4), n, nin); y <- round(0.5 * x[, 1] + 0.3 * x[, 1]^2 + rnorm(n), 4)
  qstar <- sample(1:3, 1); q <- sample(5:15, 1); rg <- sample(c(2, 4, 6), 1)
  seed <- sample(1e6, 1); set.seed(seed)
  r <- tryCatch(suppressWarnings(if (kind == 0) terasvirta.test(x, y, type = c("Chisq", "F")[ty + 1], scale = sc == 1) else white.test(x, y, qstar = qstar, q = q, range = rg, type = c("Chisq", "F")[ty + 1], scale = sc == 1)), error = function(e) NULL)
  if (is.null(r)) next
  a <- c(kind, seed, n, nin, ty, sc, qstar, q, rg, as.vector(x), y)
  add("nn", c(a, 0), as.numeric(r$statistic)); add("nn", c(a, 1), r$parameter[1]); if (ty == 1) add("nn", c(a, 2), r$parameter[2])
}
# portfolio.optim: (n, k, pm, riskless, shorts, rf, has_res, reslow[k], reshigh[k], x col-major[n*k], i) fn "po" -> weight i
for (rep in 1:80) {
  k <- sample(3:6, 1); n <- sample(80:200, 1)
  x <- matrix(rnorm(n * k, rep(runif(k, 0.0, 0.02), each = n), rep(runif(k, 0.02, 0.06), each = n)), n, k)
  riskless <- sample(0:1, 1); shorts <- sample(0:1, 1); rf <- if (riskless == 1) runif(1, 0, 0.005) else 0
  mu <- colMeans(x); pm <- if (riskless == 1) runif(1, rf + 0.001, max(mu) * 0.9 + 0.001) else runif(1, min(mu) + 0.1 * diff(range(mu)), max(mu) - 0.1 * diff(range(mu)))
  hasres <- sample(0:1, 1); lo <- rep(-0.5, k); hi <- rep(1.5, k); if (hasres == 1 && shorts == 0) { lo <- rep(0.02, k); hi <- rep(0.8, k) }
  r <- tryCatch(suppressWarnings(if (hasres == 1) portfolio.optim(x, pm = pm, riskless = riskless == 1, shorts = shorts == 1, rf = rf, reslow = lo, reshigh = hi) else portfolio.optim(x, pm = pm, riskless = riskless == 1, shorts = shorts == 1, rf = rf)), error = function(e) NULL)
  if (is.null(r)) next
  a <- c(n, k, pm, riskless, shorts, rf, hasres, lo, hi, x)
  for (i in seq_len(k)) add("po", c(a, i - 1), r$pw[i])
}
emit("tsutils", "tseries", list(cases))
