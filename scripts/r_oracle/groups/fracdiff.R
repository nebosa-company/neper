# fracdiff: diffseries, fdGPH, fdSperio.
#   args: (kind 0 diffseries 1 fdGPH 2 fdSperio, p1, p2, n, x..., pos)   p1 = d (diffseries) or bandw.exp, p2 = beta
#   fn "ds" (element pos), "dssum", "d", "sdas", "sdreg"
library(fracdiff)
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-10)
set.seed(20261115)
for (rep in 1:6) {
  n <- c(40, 64, 100, 150, 90, 200)[rep]
  x <- round(cumsum(rnorm(n)) * 0.2 + rnorm(n), 4)
  if (rep %% 2 == 0) x <- round(arima.sim(list(ar = 0.5), n), 4)
  for (d in c(-0.3, 0.1, 0.4, 0.5)) {
    v <- diffseries(x, d); a <- c(0, d, 0, n, x)
    for (i in c(1, 2, n %/% 2, n)) add("ds", c(a, i - 1), v[i])
    add("dssum", c(a, 0), sum(v))
  }
  for (bw in c(0.4, 0.5, 0.65)) {
    g <- fdGPH(x, bandw.exp = bw); a <- c(1, bw, 0, n, x)
    add("d", a, g$d); add("sdas", a, g$sd.as); add("sdreg", a, g$sd.reg)
    for (be in c(0.8, 0.9)) {
      s <- fdSperio(x, bandw.exp = bw, beta = be); a2 <- c(2, bw, be, n, x)
      add("d", a2, s$d); add("sdas", a2, s$sd.as); add("sdreg", a2, s$sd.reg)
    }
  }
}
#   fracdiff.sim: (3, seed, mu, n, d, p, q, n.start, ar[p], ma[q], pos) fn "sim" the element at pos
for (rep in 1:12) {
  n <- c(30, 60, 100)[(rep - 1) %% 3 + 1]; d <- c(-0.3, 0.2, 0.45, 0.1)[(rep - 1) %% 4 + 1]
  p <- c(0, 1, 2)[(rep - 1) %% 3 + 1]; q <- c(0, 1, 2, 1)[(rep - 1) %% 4 + 1]
  ar <- if (p) round(runif(p, -0.4, 0.4), 3) else NULL; ma <- if (q) round(runif(q, -0.6, 0.6), 3) else NULL
  ns <- if (p) 40 else q; mu <- c(0, 5)[(rep %% 2) + 1]
  set.seed(1000 + rep); s <- fracdiff.sim(n, ar = ar, ma = ma, d = d, mu = mu, n.start = ns)$series
  a <- c(3, 1000 + rep, mu, n, d, p, q, ns, ar, ma)
  for (i in c(1, 2, 3, n %/% 2, n - 1, n)) add("sim", c(a, i - 1), s[i])
  add("simsum", c(a, 0), sum(s))
}
emit("fracdiff", "fracdiff", list(cases))
