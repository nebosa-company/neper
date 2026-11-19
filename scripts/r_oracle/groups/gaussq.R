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
# qinvgauss: "igq" lower, "igqu" upper tail, "igql" log p lower; args (p, mean, dispersion)
for (rep in 1:80) {
  mu <- c(0.3, 1, 2.5, 8)[sample(4, 1)]; phi <- c(0.05, 0.4, 1, 3, 12)[sample(5, 1)]; pr <- c(1e-8, 1e-4, 0.01, 0.2, 0.5, 0.8, 0.99, 0.9999, 1 - 1e-8)[sample(9, 1)]
  add("igq", c(pr, mu, phi), qinvgauss(pr, mu, dispersion = phi)); add("igqu", c(pr, mu, phi), qinvgauss(pr, mu, dispersion = phi, lower.tail = FALSE))
  add("igql", c(log(pr), mu, phi), qinvgauss(log(pr), mu, dispersion = phi, log.p = TRUE))
}
# qresiduals: "qres" (seed, family, n, disp, y[n], mu[n], w[n], position + 1 as a sum weight) answered as sum(position * residual); family 0 binomial 1 Poisson 2 gamma 3 inverse Gaussian 4 negative binomial (disp = theta)
for (rep in 1:30) {
  fam <- rep %% 5; n <- sample(6:40, 1); sd <- sample(1:100000, 1); w <- rep(1, n); disp <- 1; mu <- runif(n, 0.5, 6)
  if (fam == 0) { w <- sample(2:12, n, TRUE); mu <- runif(n, 0.1, 0.9); y <- rbinom(n, w, mu) / w; obj <- list(family = list(family = "binomial"), y = y, fitted.values = mu, prior.weights = w) }
  if (fam == 1) { y <- rpois(n, mu); obj <- list(family = list(family = "poisson"), y = y, fitted.values = mu) }
  if (fam == 2) { disp <- runif(1, 0.2, 1.5); y <- rgamma(n, 1 / disp, scale = mu * disp); obj <- list(family = list(family = "Gamma"), y = y, fitted.values = mu, df.residual = n - 2, prior.weights = w) }
  if (fam == 3) { disp <- runif(1, 0.2, 1.5); y <- rinvgauss(n, mu, dispersion = disp); obj <- list(family = list(family = "inverse.gaussian"), y = y, fitted.values = mu, df.residual = n - 2, prior.weights = w) }
  if (fam == 4) { disp <- sample(c(1, 2.5, 6), 1); y <- rnbinom(n, size = disp, mu = mu); obj <- list(family = list(family = "Negative Binomial(2)"), y = y, fitted.values = mu, theta = disp) }
  set.seed(sd); q <- qresiduals(obj, dispersion = if (fam %in% 2:3) disp else NULL)
  add("qres", c(sd, fam, n, disp, y, mu, w, 0), sum(seq_len(n) * q))
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
  set.seed(sd); add("pftg", c(p1, p2, n1, n2, 0.05, ns, sd), power.fisher.test(p1, p2, n1, n2, alpha = 0.05, nsim = ns, alternative = "greater"))
  set.seed(sd); add("pftl", c(p1, p2, n1, n2, 0.05, ns, sd), power.fisher.test(p1, p2, n1, n2, alpha = 0.05, nsim = ns, alternative = "less"))
}
# the tweedie family object "twd": (which 0 dev.resids 1 variance 2 linkfun 3 linkinv 4 mu.eta, var.power, link.power, y, mu, wt)
for (rep in 1:40) {
  pw <- sample(c(0, 0.5, 1, 1.3, 1.5, 2, 2.4, 3), 1); lm <- sample(c(0, 0.5, 1, -1, 1 - pw), 1); if (lm == 0 && runif(1) < 0.3) lm <- 0
  fam <- statmod::tweedie(var.power = pw, link.power = lm); y <- if (runif(1) < 0.2) 0 else rexp(1) * 3; mu <- runif(1, 0.3, 5); wt <- runif(1, 0.5, 2)
  add("twd", c(0, pw, lm, y, mu, wt), fam$dev.resids(y, mu, wt)); add("twd", c(1, pw, lm, y, mu, wt), fam$variance(mu))
  add("twd", c(2, pw, lm, y, mu, wt), fam$linkfun(mu)); add("twd", c(3, pw, lm, y, mu, wt), fam$linkinv(mu)); add("twd", c(4, pw, lm, y, mu, wt), fam$mu.eta(mu))
}
# tweedie dtweedie (kind 0) and ptweedie (kind 1) for 1 < power < 2: "twpg" (kind, y, power, mu, phi)
suppressMessages(library(tweedie))
for (rep in 1:40) { pw <- runif(1, 1.1, 1.9); mu <- runif(1, 0.5, 6); ph <- runif(1, 0.3, 3); y <- if (runif(1) < 0.15) 0 else rexp(1) * mu
  cases[[length(cases) + 1]] <- case("twpg", c(0, y, pw, mu, ph), dtweedie(y, power = pw, mu = mu, phi = ph), rel = 1e-8, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("twpg", c(1, y, pw, mu, ph), ptweedie(y, power = pw, mu = mu, phi = ph), rel = 1e-6, abs = 1e-10) }
# rtweedie for 1 < power < 2 under set.seed: "twr" (seed, n, power, mu, phi, index)
for (rep in 1:15) { pw <- runif(1, 1.1, 1.9); mu <- runif(1, 0.5, 6); ph <- runif(1, 0.3, 3); sd <- sample(1:100000, 1); nn <- sample(5:15, 1); set.seed(sd); rt <- rtweedie(nn, power = pw, mu = mu, phi = ph)
  for (q in c(1, nn %/% 2, nn)) cases[[length(cases) + 1]] <- case("twr", c(sd, nn, pw, mu, ph, q - 1), rt[q], rel = 1e-10, abs = 1e-12) }
# qtweedie for 1 < power < 2: "twq" (prob, power, mu, phi)
for (rep in 1:30) { pw <- runif(1, 1.1, 1.9); mu <- runif(1, 0.5, 6); ph <- runif(1, 0.3, 3); pr <- runif(1, 0.02, 0.98)
  cases[[length(cases) + 1]] <- case("twq", c(pr, pw, mu, ph), qtweedie(pr, power = pw, mu = mu, phi = ph), rel = 1e-8, abs = 1e-10) }
# dtweedie_saddle: "tws" (y, power, mu, phi), powers on both sides of 2 and the atom at 0
for (rep in 1:40) { pw <- c(runif(1, 1.1, 1.9), runif(1, 2.2, 3.5))[rep %% 2 + 1]; mu <- runif(1, 0.5, 6); ph <- runif(1, 0.3, 3); y <- if (rep %% 7 == 0 && pw < 2) 0 else rexp(1) * mu + 0.05
  cases[[length(cases) + 1]] <- case("tws", c(y, pw, mu, ph), dtweedie_saddle(y, power = pw, mu = mu, phi = ph), rel = 1e-10, abs = 1e-12) }
# tweedie dtweedie_series for power > 2: "twb" (y, power, mu, phi); only the points where the package's series is reliable (not NaN)
suppressWarnings({
for (rep in 1:60) {
  pw <- runif(1, 2.1, 4.5); mu <- runif(1, 0.5, 4); ph <- runif(1, 0.3, 2); y <- rexp(1, 1 / mu) + 0.05
  d <- suppressWarnings(tryCatch(dtweedie_series(y, power = pw, mu = mu, phi = ph), error = function(e) NaN))
  if (!is.finite(d) || d <= 0) next
  cases[[length(cases) + 1]] <- case("twb", c(y, pw, mu, ph), d, rel = 1e-9, abs = 1e-14)
}
})
emit("gaussq", "statmod", list(cases))
