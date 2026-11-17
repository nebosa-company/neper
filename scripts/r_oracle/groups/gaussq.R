# statmod gauss.quad and gauss.quad.prob: every node and weight.
#   args: (fn id, n, p1, p2, p3, p4, i)  gauss.quad: id 0..5 kinds, p1 alpha, p2 beta; gauss.quad.prob: id 10..15 dists uniform beta1 beta2 normal beta gamma,
#   p1 l / mu / alpha, p2 u / sigma / beta; fn "node" "weight" (index i)
suppressMessages(library(statmod))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
kinds <- c("legendre", "chebyshev1", "chebyshev2", "hermite", "jacobi", "laguerre")
dists <- c("uniform", "beta1", "beta2", "normal", "beta", "gamma")
for (n in c(1, 2, 3, 5, 8, 15, 30)) {
  for (k in 0:5) {
    al <- c(0, 0, 0, 0, 0.7, 1.3)[k + 1]; be <- c(0, 0, 0, 0, 1.9, 0)[k + 1]
    r <- gauss.quad(n, kinds[k + 1], alpha = al, beta = be)
    for (i in seq_len(n)) { add("node", c(k, n, al, be, 0, 0, i - 1), r$nodes[i]); add("weight", c(k, n, al, be, 0, 0, i - 1), r$weights[i]) }
  }
  for (d in 0:5) {
    p1 <- c(-1, 0, 0, 2, 2.5, 3)[d + 1]; p2 <- c(4, 0, 0, 1.5, 1.2, 0.8)[d + 1]
    r <- if (d == 0) gauss.quad.prob(n, dists[d + 1], l = p1, u = p2) else if (d == 3) gauss.quad.prob(n, dists[d + 1], mu = p1, sigma = p2) else if (d >= 4) gauss.quad.prob(n, dists[d + 1], alpha = p1, beta = p2) else gauss.quad.prob(n, dists[d + 1])
    for (i in seq_len(n)) { add("node", c(10 + d, n, p1, p2, 0, 0, i - 1), r$nodes[i]); add("weight", c(10 + d, n, p1, p2, 0, 0, i - 1), r$weights[i]) }
  }
}
# the inverse Gaussian: "igd" density, "igdl" log density, "igp" cdf, "igpu" upper tail, "igpl" log cdf args (x, mean, dispersion); "igr" args (n, mean, dispersion, seed, index) after set.seed
for (rep in 1:60) {
  mu <- c(0.3, 1, 2.5, 8)[sample(4, 1)]; phi <- c(0.05, 0.4, 1, 3, 12)[sample(5, 1)]; x <- mu * c(0.1, 0.5, 1, 1.7, 4, 12)[sample(6, 1)]
  add("igd", c(x, mu, phi), dinvgauss(x, mu, dispersion = phi)); add("igdl", c(x, mu, phi), dinvgauss(x, mu, dispersion = phi, log = TRUE))
  add("igp", c(x, mu, phi), pinvgauss(x, mu, dispersion = phi)); add("igpu", c(x, mu, phi), pinvgauss(x, mu, dispersion = phi, lower.tail = FALSE)); add("igpl", c(x, mu, phi), pinvgauss(x, mu, dispersion = phi, log.p = TRUE))
}
for (rep in 1:12) {
  n <- sample(5:30, 1); mu <- c(0.5, 1, 3)[sample(3, 1)]; phi <- c(0.1, 1, 6)[sample(3, 1)]; sd <- sample(1:100000, 1)
  set.seed(sd); r <- rinvgauss(n, mu, dispersion = phi)
  for (k in seq_len(n)) add("igr", c(n, mu, phi, sd, k - 1), r[k])
}
# permp: args (x, nperm, n1, n2, total.nperm or 0, method 0 auto 1 exact 2 approximate, twosided)
for (rep in 1:80) {
  n1 <- sample(3:9, 1); n2 <- if (rep %% 3 == 0) n1 else sample(3:9, 1); nperm <- sample(c(50, 200, 1000, 5000), 1); x <- sample(0:min(nperm, 40), 1)
  me <- sample(0:2, 1); ts <- rep %% 2 == 0; tot <- if (rep %% 5 == 0) sample(c(300, 5000, 20000), 1) else 0
  v <- tryCatch(permp(x, nperm, n1, n2, total.nperm = if (tot > 0) tot else NULL, method = c("auto", "exact", "approximate")[me + 1], twosided = ts), error = function(e) NA)
  add("permp", c(x, nperm, n1, n2, tot, me, as.numeric(ts)), v)
}
# power.fisher.test after set.seed: args (p1, p2, n1, n2, alpha, nsim, seed)
for (rep in 1:30) {
  p1 <- round(runif(1, 0.1, 0.5), 2); p2 <- round(p1 + runif(1, 0.1, 0.4), 2); n1 <- sample(c(10, 20, 40, 80), 1); n2 <- sample(c(10, 20, 40, 80), 1); sd <- sample(1:100000, 1); ns <- sample(c(50, 100, 200), 1)
  set.seed(sd); v <- power.fisher.test(p1, p2, n1, n2, alpha = 0.05, nsim = ns)
  add("pft", c(p1, p2, n1, n2, 0.05, ns, sd), v)
}
emit("gaussq", "statmod", list(cases))
