# mediation::mediate beyond the linear case: a gaussian, probit, logit or poisson mediator model and a gaussian, logit or probit outcome model (treatment 0/1, one covariate), with or without the treatment-mediator
# interaction, quasi-Bayesian (mode 0) and nonparametric bootstrap with percentile (mode 1) or BCa (mode 2) limits. The data are drawn inside the case from the seed (the fixture repeats the draws with the
# same R stream), so a case is (mtype, ytype, int, mode, s1, n, sims, conf, s2, q): mtype 0 gaussian, 1 probit, 2 logit, 3 poisson; ytype 0 gaussian, 1 logit, 2 probit; q = 4 * quantity + k, quantity in the order
# d0, d1, z0, z1, n0, n1, tau.coef, d.avg, z.avg, n.avg and k 0 estimate, 1 lower limit, 2 upper limit, 3 p value.
suppressMessages(library(mediation))
cases <- list()
one <- function(mtype, ytype, int, mode, s1, n, sims, conf, s2) {
  set.seed(s1)
  x <- rnorm(n); tr <- rbinom(n, 1, 0.5)
  m <- if (mtype == 0) 0.5 * tr + 0.3 * x + rnorm(n)
       else if (mtype == 3) rpois(n, 1 + 0.8 * tr + 0.4 * (x > 0))
       else rbinom(n, 1, 0.25 + 0.3 * tr + 0.15 * (x > 0))
  y <- if (ytype == 0) 0.4 * tr + 0.6 * m + 0.2 * x + 0.3 * int * tr * m + rnorm(n)
       else rbinom(n, 1, 0.3 + 0.2 * tr + 0.15 * (m > 0) + 0.1 * (x > 0))
  d <- data.frame(tr = tr, m = m, y = y, x = x)
  mm <- if (mtype == 0) lm(m ~ tr + x, d) else if (mtype == 3) glm(m ~ tr + x, family = poisson(), data = d) else if (mtype == 1) glm(m ~ tr + x, family = binomial("probit"), data = d) else glm(m ~ tr + x, family = binomial("logit"), data = d)
  my <- if (ytype == 0 && int == 0) lm(y ~ tr + m + x, d) else if (ytype == 0) lm(y ~ tr * m + x, d)
        else if (ytype == 1 && int == 0) glm(y ~ tr + m + x, family = binomial("logit"), data = d) else if (ytype == 1) glm(y ~ tr * m + x, family = binomial("logit"), data = d)
        else if (int == 0) glm(y ~ tr + m + x, family = binomial("probit"), data = d) else glm(y ~ tr * m + x, family = binomial("probit"), data = d)
  set.seed(s2)
  r <- suppressMessages(mediate(mm, my, treat = "tr", mediator = "m", sims = sims, conf.level = conf, boot = mode > 0, boot.ci.type = if (mode == 2) "bca" else "perc"))
  v <- c(r$d0, r$d0.ci, r$d0.p, r$d1, r$d1.ci, r$d1.p, r$z0, r$z0.ci, r$z0.p, r$z1, r$z1.ci, r$z1.p, r$n0, r$n0.ci, r$n0.p, r$n1, r$n1.ci, r$n1.p,
         r$tau.coef, r$tau.ci, r$tau.p, r$d.avg, r$d.avg.ci, r$d.avg.p, r$z.avg, r$z.avg.ci, r$z.avg.p, r$n.avg, r$n.avg.ci, r$n.avg.p)
  lapply(seq_along(v), function(q) case("med2", c(mtype, ytype, int, mode, s1, n, sims, conf, s2, q - 1), as.numeric(v[q]), rel = 1e-9, abs = 1e-12))
}
# mtype, ytype, int, mode, s1, n, sims, conf, s2
cases <- c(cases, one(0, 0, 1, 0, 4101, 70, 300, 0.95, 4102))
cases <- c(cases, one(1, 0, 0, 0, 4111, 80, 250, 0.9, 4112))
cases <- c(cases, one(2, 0, 1, 0, 4121, 80, 250, 0.95, 4122))
cases <- c(cases, one(0, 1, 0, 0, 4131, 90, 300, 0.95, 4132))
cases <- c(cases, one(2, 1, 1, 0, 4141, 90, 250, 0.9, 4142))
cases <- c(cases, one(3, 1, 0, 0, 4151, 70, 250, 0.95, 4152))
cases <- c(cases, one(0, 2, 1, 0, 4161, 90, 250, 0.95, 4162))
cases <- c(cases, one(0, 0, 0, 1, 4171, 60, 150, 0.95, 4172))
cases <- c(cases, one(1, 0, 1, 1, 4181, 70, 120, 0.9, 4182))
cases <- c(cases, one(0, 1, 1, 1, 4191, 80, 120, 0.95, 4192))
cases <- c(cases, one(2, 1, 0, 2, 4201, 80, 150, 0.95, 4202))
cases <- c(cases, one(0, 0, 1, 2, 4211, 60, 150, 0.95, 4212))
emit("mediation2", "mediation", list(cases))
