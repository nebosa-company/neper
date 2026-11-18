# survreg for right-censored data: args (dist code 0 weibull / 1 exponential / 2 lognormal / 3 loglogistic / 4 gaussian / 5 logistic, n, p (with the intercept column), time, status, X column-major, q)
# q 0..p-1 coefficients, p the scale, p + 1 the log-likelihood, p + 2.. the standard errors of (beta, log scale)
suppressMessages(library(survival))
cases <- list()
set.seed(20262803)
dn <- c("weibull", "exponential", "lognormal", "loglogistic", "gaussian", "logistic")
for (rep in 1:30) {
  d <- sample(0:5, 1); n <- sample(40:90, 1); p <- 2; xv <- round(rnorm(n), 2); X <- cbind(1, xv)
  eta <- 2 + 0.5 * xv
  t <- switch(d + 1, rweibull(n, 2, exp(eta)), rexp(n, exp(-eta)), exp(eta + rnorm(n, 0, 0.7)), exp(eta + rlogis(n, 0, 0.4)), eta + rnorm(n, 0, 0.9) + 5, eta + rlogis(n, 0, 0.5) + 5, eta - log(rexp(n)) + 5)
  t <- round(pmax(t, 0.05), 3); cens <- rexp(n, 0.1) * 3; st <- as.numeric(t <= cens); tm <- pmin(t, cens)
  if (sum(st) < 12) next
  f <- tryCatch(survreg(Surv(tm, st) ~ xv, dist = dn[d + 1], control = survreg.control(rel.tolerance = 1e-12)), error = function(e) NULL)
  if (is.null(f)) next
  a <- c(d, n, p, tm, st, X)
  out <- c(coef(f), f$scale, f$loglik[2], sqrt(diag(f$var)))
  for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("sreg", c(a, q - 1), out[q], rel = 1e-5, abs = 1e-7)
}
emit("survreg", "survival", list(cases))
