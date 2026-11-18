# gamlss.dist's make.link.gamlss: args (kind, what, x) with what 0 linkfun(mu = x), 1 linkinv(eta = x), 2 mu.eta(eta = x); kinds 0 logit, 1 probit, 2 cauchit, 3 cloglog,
# 4 identity, 5 log, 6 sqrt, 7 1/mu^2, 8 mu^2, 9 logshiftto1, 10 logshiftto2, 11 logshiftto0
suppressMessages(library(gamlss.dist))
cases <- list()
nm <- c("logit", "probit", "cauchit", "cloglog", "identity", "log", "sqrt", "1/mu^2", "mu^2", "logshiftto1", "logshiftto2", "logshiftto0")
set.seed(20262201)
for (k in 0:11) {
  lk <- make.link.gamlss(nm[k + 1])
  mus <- if (k %in% 0:3) runif(5, 0.02, 0.98) else if (k == 9) 1 + runif(5, 0.1, 5) else if (k == 10) 2 + runif(5, 0.1, 5) else runif(5, 0.2, 6)
  etas <- if (k %in% c(6, 7, 8)) runif(5, 0.2, 4) else rnorm(5, 0, 2)
  for (m in mus) cases[[length(cases) + 1]] <- case("l", c(k, 0, m), lk$linkfun(m), rel = 1e-10, abs = 1e-12)
  for (e in etas) {
    cases[[length(cases) + 1]] <- case("l", c(k, 1, e), lk$linkinv(e), rel = 1e-10, abs = 1e-12)
    cases[[length(cases) + 1]] <- case("l", c(k, 2, e), lk$mu.eta(e), rel = 1e-10, abs = 1e-12)
  }
}
emit("gamlss_link", "gamlss.dist", list(cases))
