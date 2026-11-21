# mediation::medsens (sensitivity of mediate's effects to the correlation rho of the two models' errors). A case is (kind, int, s1, n, rho.by, conf, sims, s2, idx): the data are drawn from s1 (the fixture repeats the
# draws), kind 0 a gaussian mediator and gaussian outcome (with the treatment-mediator interaction when int is 1), kind 1 a gaussian mediator and probit outcome, kind 2 a probit mediator and gaussian outcome (int as for kind 0); s2 seeds medsens. idx addresses the flattened output:
# 26 blocks of nr values (rho = seq(-1 + rho.by, 1 - rho.by, rho.by)) in the order d0, lower.d0, upper.d0, d1, ..., z0, ..., z1, ..., tau, ..., nu0, ..., nu1, ..., then ind.d0, ind.d1, ind.z0, ind.z1,
# R2tilde.prod, then 14 scalars: err.cr.d (2), err.cr.z (2), r.square.m, r.square.y, then R2star.d.thresh and R2tilde.d.thresh of d0, d1 and the same for z. Entries R leaves NULL or NA have no case.
suppressMessages(library(mediation))
blocks <- c("d0", "lower.d0", "upper.d0", "d1", "lower.d1", "upper.d1", "z0", "lower.z0", "upper.z0", "z1", "lower.z1", "upper.z1", "tau", "lower.tau", "upper.tau",
            "nu0", "lower.nu0", "upper.nu0", "nu1", "lower.nu1", "upper.nu1", "ind.d0", "ind.d1", "ind.z0", "ind.z1", "R2tilde.prod")
two <- function(v) c(v[1], if (length(v) > 1) v[2] else NA)
one <- function(kind, int, s1, n, by, conf, sims, s2, rel = 1e-9) {
  set.seed(s1)
  x <- rnorm(n); tr <- rbinom(n, 1, 0.5)
  m <- if (kind == 2) rbinom(n, 1, 0.25 + 0.3 * tr + 0.15 * (x > 0)) else 0.5 * tr + 0.3 * x + rnorm(n)
  y <- if (kind != 1) 0.4 * tr + 0.6 * m + 0.2 * x + 0.3 * int * tr * m + rnorm(n) else rbinom(n, 1, 0.3 + 0.2 * tr + 0.15 * (m > 0) + 0.1 * (x > 0))
  d <- data.frame(tr = tr, m = m, y = y, x = x)
  mm <- if (kind == 2) glm(m ~ tr + x, family = binomial("probit"), data = d) else lm(m ~ tr + x, d)
  my <- if (kind != 1 && int == 0) lm(y ~ tr + m + x, d) else if (kind != 1) lm(y ~ tr * m + x, d) else glm(y ~ tr + m + x, family = binomial("probit"), data = d)
  md <- suppressMessages(mediate(mm, my, treat = "tr", mediator = "m", sims = 20, conf.level = conf))
  set.seed(s2)
  s <- suppressWarnings(medsens(md, rho.by = by, sims = sims, effect.type = "both"))
  nr <- length(s$rho)
  sd <- two(s$R2star.d.thresh); td <- two(s$R2tilde.d.thresh); sz <- two(s$R2star.z.thresh); tz <- two(s$R2tilde.z.thresh)
  v <- c(unlist(lapply(blocks, function(nm) { e <- s[[nm]]; if (is.null(e)) rep(NA_real_, nr) else as.numeric(e) })),
         two(s$err.cr.d), two(s$err.cr.z), s$r.square.m, s$r.square.y, sd[1], td[1], sd[2], td[2], sz[1], tz[1], sz[2], tz[2])
  keep <- which(!is.na(v))
  lapply(keep, function(q) case("medsens", c(kind, int, s1, n, by, conf, sims, s2, q - 1), v[q], rel = rel, abs = 1e-12))
}
cases <- list()
cases <- c(cases, one(0, 0, 5101, 60, 0.1, 0.95, 10, 5102))
cases <- c(cases, one(0, 1, 5111, 70, 0.1, 0.95, 10, 5112))
cases <- c(cases, one(0, 1, 5121, 80, 0.25, 0.9, 10, 5122))
cases <- c(cases, one(1, 0, 5131, 80, 0.2, 0.95, 40, 5132))
cases <- c(cases, one(1, 0, 5141, 90, 0.1, 0.9, 30, 5142))
cases <- c(cases, one(2, 0, 5151, 60, 0.2, 0.95, 15, 5152))
cases <- c(cases, one(2, 1, 5161, 60, 0.25, 0.9, 12, 5162))
emit("medsens", "mediation", list(cases))
