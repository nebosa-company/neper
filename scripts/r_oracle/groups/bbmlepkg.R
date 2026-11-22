# bbmlepkg: bbmle::mle2 (default BFGS, numerical gradient, numDeriv Hessian), profile, confint (spline and quad) and AICtab / BICtab / AICctab, on the five log-likelihoods of maxlikpkg written as minus sums.
#   models: 0 normal (mu, sigma), 1 poisson regression (b0, b1), 2 logistic regression (b0, b1), 3 Weibull (shape, scale), 4 linear regression (b0, b1, s)
#   "bb_mle2"  (what, j, model, n, start (p), x (n), y (n)): what 0 coef[j], 1 min (minus log-likelihood), 2 stdEr[j]
#   "bb_prof"  (what, i, k, j, model, n, start, x, y): profile(fit, which = i): what 0 the number of points, 1 z[k], 2 par.vals[k, j] (sorted by parameter i)
#   "bb_ci"    (what, i, side, model, n, start, x, y): what 0 confint(fit, i) by the spline method, 1 by "quad"; side 0 lower, 1 upper
#   "bb_ic"    (what, k, type, n, start normal (2), start Weibull (2), start exponential Weibull (1), x (n)): AICtab / BICtab / AICctab (type 0, 1, 2) of normal, Weibull and Weibull with shape fixed at 1,
#              weights = TRUE: what 0 the model (1 based) in row k of the sorted table, 1 the delta, 2 df, 3 weight
#   tolerances are in the add() calls: mle2, profile and confint depend on optim's BFGS ending, which R itself moves with the summation precision (see maxlikpkg), so they carry 1e-6
suppressMessages(library(bbmle))
cases <- list()
add <- function(fn, args, want, rel, abs = 0) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
npar <- c(2, 2, 2, 2, 3)
pn <- list(c("mu", "sigma"), c("b0", "b1"), c("b0", "b1"), c("shape", "scale"), c("b0", "b1", "s"))
nlls <- list(
  function(mu, sigma) -sum(-0.5 * log(2 * pi) - log(sigma) - (x - mu) * (x - mu) / (2 * sigma * sigma)),
  function(b0, b1) { eta <- b0 + b1 * x; -sum(y * eta - exp(eta)) },
  function(b0, b1) { eta <- b0 + b1 * x; -sum(y * eta - log(1 + exp(eta))) },
  function(shape, scale) -sum(log(shape) - shape * log(scale) + (shape - 1) * log(x) - (x / scale)^shape),
  function(b0, b1, s) { r <- y - b0 - b1 * x; -sum(-0.5 * log(2 * pi) - log(s) - r * r / (2 * s * s)) })
fitm <- function(m, st, x, y) {
  f <- nlls[[m + 1]]; environment(f) <- environment()
  suppressWarnings(suppressMessages(mle2(f, start = setNames(as.list(st), pn[[m + 1]]), data = list(x = x, y = y))))
}
set.seed(20262811)
for (rep in 1:25) {
  m <- (rep - 1) %% 5; n <- sample(20:35, 1)
  if (m == 0) { tr <- c(runif(1, -2, 2), runif(1, 0.5, 3)); x <- round(rnorm(n, tr[1], tr[2]), 3); y <- rep(0, n); st <- tr * runif(2, 0.7, 1.3) + c(0.2, 0) }
  if (m == 1) { tr <- c(runif(1, -0.5, 1), runif(1, -1, 1)); x <- round(runif(n, -1, 1), 3); y <- rpois(n, exp(tr[1] + tr[2] * x)); st <- tr + runif(2, -0.5, 0.5) }
  if (m == 2) { tr <- c(runif(1, -1, 1), runif(1, -2, 2)); x <- round(rnorm(n), 3); y <- rbinom(n, 1, 1 / (1 + exp(-(tr[1] + tr[2] * x)))); st <- tr + runif(2, -0.7, 0.7) }
  if (m == 3) { tr <- c(runif(1, 0.8, 3), runif(1, 0.5, 3)); x <- pmax(round(rweibull(n, tr[1], tr[2]), 3), 0.001); y <- rep(0, n); st <- tr * runif(2, 0.8, 1.25) }
  if (m == 4) { tr <- c(runif(1, -1, 1), runif(1, -2, 2), runif(1, 0.3, 2)); x <- round(runif(n, -1, 2), 3); y <- round(tr[1] + tr[2] * x + rnorm(n, 0, tr[3]), 3); st <- tr * runif(3, 0.8, 1.25) }
  st <- round(st, 3); p <- npar[m + 1]
  fit <- tryCatch(fitm(m, st, x, y), error = function(e) NULL)
  if (is.null(fit)) next
  se <- sqrt(diag(fit@vcov))
  if (any(!is.finite(se)) || any(!is.finite(coef(fit)))) next
  hd <- function(what, j) c(what, j, m, n, st, x, y)
  for (j in seq_len(p)) { add("bb_mle2", hd(0, j - 1), coef(fit)[j], 1e-6); add("bb_mle2", hd(2, j - 1), se[j], 1e-6) }
  add("bb_mle2", hd(1, 0), fit@min, 1e-9)
  i <- (rep %% p) + 1
  pr <- tryCatch(suppressWarnings(suppressMessages(profile(fit, which = i))), error = function(e) NULL)
  if (!is.null(pr) && is(pr, "profile.mle2")) {
    pf <- pr@profile[[pn[[m + 1]][i]]]; pv <- as.matrix(pf$par.vals); nr <- nrow(pv)
    add("bb_prof", c(0, i - 1, 0, 0, m, n, st, x, y), nr, 0)
    for (k in seq_len(nr)) {
      add("bb_prof", c(1, i - 1, k - 1, 0, m, n, st, x, y), pf$z[k], 1e-6, 1e-9)
      for (j in seq_len(p)) add("bb_prof", c(2, i - 1, k - 1, j - 1, m, n, st, x, y), pv[k, j], 1e-5)
    }
    ci <- tryCatch(suppressWarnings(confint(pr, parm = i)), error = function(e) NULL)
    if (!is.null(ci) && all(is.finite(ci))) for (s in 1:2) add("bb_ci", c(0, i - 1, s - 1, m, n, st, x, y), ci[s], 1e-6)
  }
  cq <- suppressWarnings(confint(fit, method = "quad", parm = i))
  for (s in 1:2) add("bb_ci", c(1, i - 1, s - 1, m, n, st, x, y), cq[s], 1e-6)
}
# information criteria on one positive sample per replicate: normal, Weibull, Weibull with the shape fixed at 1
for (rep in 1:24) {
  n <- sample(25:60, 1); tr <- c(runif(1, 0.8, 3), runif(1, 0.5, 3)); x <- pmax(round(rweibull(n, tr[1], tr[2]), 3), 0.001); y <- rep(0, n)
  s1 <- round(c(mean(x), sd(x)) * runif(2, 0.9, 1.1), 3); s2 <- round(tr * runif(2, 0.85, 1.2), 3); s3 <- round(mean(x) * runif(1, 0.9, 1.1), 3)
  f1 <- nlls[[1]]; f2 <- nlls[[4]]; f3 <- function(shape, scale) -sum(log(shape) - shape * log(scale) + (shape - 1) * log(x) - (x / scale)^shape)
  environment(f1) <- environment(f2) <- environment(f3) <- environment()
  r <- tryCatch(suppressWarnings(suppressMessages({
    m1 <- mle2(f1, start = list(mu = s1[1], sigma = s1[2]), data = list(x = x))
    m2 <- mle2(f2, start = list(shape = s2[1], scale = s2[2]), data = list(x = x))
    m3 <- mle2(f3, start = list(scale = s3), fixed = list(shape = 1), data = list(x = x))
    TRUE})), error = function(e) NULL)
  if (is.null(r)) next
  for (type in 0:2) {
    tb <- suppressWarnings(switch(type + 1, AICtab(m1, m2, m3, weights = TRUE, mnames = c("1", "2", "3")),
                                  BICtab(m1, m2, m3, weights = TRUE, nobs = n, mnames = c("1", "2", "3")),
                                  AICctab(m1, m2, m3, weights = TRUE, nobs = n, mnames = c("1", "2", "3"))))
    tb <- as.data.frame(tb); dn <- grep("^d", names(tb), value = TRUE)[1]
    for (k in 1:3) {
      a <- c(0, k - 1, type, n, s1, s2, s3, x)
      add("bb_ic", a, as.numeric(rownames(tb)[k]), 0)
      a[1] <- 1; add("bb_ic", a, tb[[dn]][k], 1e-9, 1e-9)
      a[1] <- 2; add("bb_ic", a, tb$df[k], 0)
      a[1] <- 3; add("bb_ic", a, tb$weight[k], 1e-9, 1e-9)
    }
  }
}
emit("bbmlepkg", "bbmle", list(cases))
