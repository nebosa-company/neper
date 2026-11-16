# extraDistr: d, p and q of sixteen closed-form continuous distributions.
#   args: (dist, p1, p2, p3, v) fn "d" "p" "q"; dist 0 gumbel(mu, sigma) 1 frechet(lambda, mu, sigma) 2 kumar(a, b) 3 laplace(mu, sigma) 4 lomax(lambda, kappa)
#   5 pareto(a, b) 6 rayleigh(sigma) 7 triang(a, b, c) 8 gompertz(a, b) 9 power(alpha, beta) 10 invgamma(alpha, beta) 11 hnorm(sigma) 12 hcauchy(sigma)
#   13 fatigue(alpha, beta, mu) 14 wald(mu, lambda) (no q) 15 betapr(alpha, beta, sigma)
suppressMessages(library(extraDistr))
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261130)
names0 <- c("gumbel", "frechet", "kumar", "laplace", "lomax", "pareto", "rayleigh", "triang", "gompertz", "power", "invgamma", "hnorm", "hcauchy", "fatigue", "wald", "betapr")
npar <- c(2, 3, 2, 2, 2, 2, 1, 3, 2, 2, 2, 1, 1, 3, 2, 3)
for (rep in 1:4) for (di in 0:15) {
  nm <- names0[di + 1]
  pr <- switch(di + 1, c(0.4, 1.3), c(2.5, 0.2, 1.4), c(1.7, 2.3), c(-0.3, 0.9), c(0.8, 2.6), c(2.2, 1.1), 1.4, c(0.1, 3.2, 1.1), c(0.7, 1.2), c(1.8, 4.5), c(2.6, 1.7), 1.3, 0.9, c(0.8, 1.9, 0.2), c(1.3, 2.2), c(2.4, 3.1, 1.2))
  pr <- pr * runif(length(pr), 0.85, 1.15)
  if (di == 7) pr <- c(0.1, 3.2, 1.1) * c(1, 1, 1)
  xs <- switch(di + 1, c(-1, 0.5, 2, 5), c(0.3, 0.8, 2, 6), c(0.2, 0.5, 0.8, 0.95), c(-2, -0.3, 0.4, 3), c(0.1, 1, 3, 9), c(1.2, 2, 5, 12), c(0.3, 1, 2.5, 4), c(0.3, 1.1, 2, 3), c(0.1, 0.8, 2, 4), c(0.4, 1.5, 3, 4.2), c(0.2, 0.7, 2, 6), c(0.2, 0.9, 2, 4), c(0.2, 0.9, 2, 7), c(0.5, 1.3, 2.5, 7), c(0.3, 1, 2.5, 6), c(0.2, 1, 3, 9))
  pp3 <- c(pr, rep(0, 3 - length(pr)))
  if (di == 7) { xs <- c(0.5, 1.1, 2, 3); pr <- c(0.1, 3.2, 1.1) }
  for (xx in xs) {
    add("d", c(di, pp3, xx), do.call(get(paste0("d", nm)), c(list(xx), as.list(pr))))
    add("p", c(di, pp3, xx), do.call(get(paste0("p", nm)), c(list(xx), as.list(pr))))
  }
  if (di != 14) for (pq in c(0.03, 0.3, 0.6, 0.95)) add("q", c(di, pp3, pq), do.call(get(paste0("q", nm)), c(list(pq), as.list(pr))))
}
emit("extradistr", "extraDistr", list(cases))
