# mediation::mediate, linear mediator and outcome models (treat 0/1, one covariate), quasi-Bayesian: "med" args (seed, sims, conf, n, tr[n], x[n], m[n], y[n], q) q = 4 * quantity + k, quantity 0 ACME (d.avg), 1 ADE (z.avg), 2 total effect, 3 proportion
# mediated (n.avg); k 0 estimate, 1 lower limit, 2 upper limit, 3 p value
suppressMessages(library(mediation))
cases <- list()
set.seed(20271201)
for (rep in 1:24) {
  n <- sample(60:200, 1); x <- rnorm(n); tr <- rbinom(n, 1, 0.5); m <- 0.5 * tr + 0.3 * x + rnorm(n); y <- 0.4 * tr + 0.6 * m + 0.2 * x + rnorm(n)
  d <- data.frame(tr = tr, m = m, y = y, x = x); sims <- sample(c(100, 200, 500), 1); cl <- sample(c(0.9, 0.95), 1); sd0 <- sample(1000:99999, 1)
  mm <- lm(m ~ tr + x, d); my <- lm(y ~ tr + m + x, d)
  set.seed(sd0); r <- suppressMessages(mediate(mm, my, treat = "tr", mediator = "m", sims = sims, conf.level = cl))
  v <- c(r$d.avg, r$d.avg.ci, r$d.avg.p, r$z.avg, r$z.avg.ci, r$z.avg.p, r$tau.coef, r$tau.ci, r$tau.p, r$n.avg, r$n.avg.ci, r$n.avg.p)
  for (q in seq_along(v)) cases[[length(cases) + 1]] <- case("med", c(sd0, sims, cl, n, tr, x, m, y, q - 1), as.numeric(v[q]), rel = 1e-8, abs = 1e-10)
}
emit("mediation", "mediation", list(cases))
