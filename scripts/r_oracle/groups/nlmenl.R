# nlme::nlme: non-linear mixed-effects models with the self-start models SSlogis, SSasymp, SSmicmen, SSfpl and SSgompertz, one grouping level,
# every parameter fixed ~ 1, random effects on a subset (full pdLogChol covariance), ML, no start values (nlme's selfStart initial values).
# case: c(kind, q_out, reml, n, ng, gs[ng], x[n], y[n], nr, rset[nr]) (rset 1-based parameter indices); output vector: fixed effects (np), sigma, logLik,
# AIC, BIC, random-effect sds (nr), their correlations (lower triangle by columns), standard errors of the fixed effects (np), ranef (group-major, groups in data order; groupedData re-levels g by the response, so rows are mapped back).
#
# nlme's alternating algorithm (Lindstrom and Bates) ends where the penalized non-linear least squares fit of (beta, b) at the current D and the ML (REML) fit
# of D on the linearisation at that fit reproduce each other. R stops that iteration at its own pnlsTol (1e-3 by default; below 1e-7 its PNLS step halves out), so
# nlme's estimates sit ~1e-4 from that fixed point. The reference here is the fixed point itself, iterated with an exact PNLS (Gauss-Newton with the analytic
# self-start gradients) and a Newton-polished ML/REML optimum of D (the objective rebuilt on the linearisation), then checked against nlme(pnlsTol = 1e-7)
# (estimates, sigma, logLik, sds to 1e-6 relative, se to 1e-5) before a case is kept. The D optimum is located to ~1e-9 on both sides: rel 1e-7 / abs 1e-8.
suppressMessages(library(nlme))
suppressMessages(library(numDeriv))
cases <- list()
set.seed(20261122)
source(file.path(root, "scripts", "r_oracle", "nlme_fixpoint.R"))
mkd <- function(kind, ng, m) {
  tru <- list(c(10, 6, 1.5), c(10, 2, -0.5), c(200, 0.1), c(1, 9, 5, 1.2), c(8, 3, 0.7))[[kind]]
  xs <- list(seq(1, 12, length.out = m), seq(0.5, 8, length.out = m), seq(0.02, 1.1, length.out = m), seq(0, 10, length.out = m), seq(1, m * 2, length.out = m))[[kind]]
  sdr <- list(c(1.5, 0.6, 0.15), c(1, 0.5, 0.15), c(15, 0.03), c(0.5, 0.9, 0.4, 0.15), c(0.7, 0.3, 0.05))[[kind]]; sde <- list(0.3, 0.2, 4, 0.1, 0.15)[[kind]]
  x <- rep(round(xs, 3), ng); g <- rep(seq_len(ng), each = m)
  RE <- matrix(rnorm(ng * length(tru)), ng, length(tru)) * rep(sdr, each = ng)
  y <- numeric(length(x))
  for (t in seq_along(x)) y[t] <- as.numeric(ssmod[[kind]](x[t], tru + RE[g[t], ])) + rnorm(1, 0, sde)
  groupedData(y ~ x | g, data.frame(y = round(y, 4), x = x, g = factor(g)))
}
fms <- list(y ~ SSlogis(x, Asym, xmid, scal), y ~ SSasymp(x, Asym, R0, lrc), y ~ SSmicmen(x, Vm, K), y ~ SSfpl(x, A, B, xmid, scal), y ~ SSgompertz(x, Asym, b2, b3))
pn <- list(c("Asym", "xmid", "scal"), c("Asym", "R0", "lrc"), c("Vm", "K"), c("A", "B", "xmid", "scal"), c("Asym", "b2", "b3"))
# cfg: kind, rset, reml, groups, group size
cfgs <- list(list(1, 1, 0, 8, 7), list(1, c(1, 2), 0, 8, 8), list(2, 1, 0, 8, 7), list(3, 1, 0, 8, 7), list(4, 1, 0, 8, 8), list(5, 1, 0, 8, 9), list(5, c(1, 3), 0, 9, 9), list(1, 1, 1, 8, 7), list(1, c(1, 2), 1, 8, 8), list(2, 1, 1, 8, 7), list(4, 1, 1, 8, 8), list(5, c(1, 3), 1, 9, 9))
for (cf in cfgs) {
  kind <- cf[[1]]; rs <- cf[[2]]; reml <- cf[[3]]
  d <- mkd(kind, cf[[4]], cf[[5]]); np <- length(pn[[kind]])
  fx <- as.formula(paste(paste(pn[[kind]], collapse = " + "), "~ 1")); rd <- as.formula(paste(paste(pn[[kind]][rs], collapse = " + "), "~ 1 | g"))
  ctl <- nlmeControl(pnlsTol = 1e-7, tolerance = 1e-9, msTol = 1e-12, pnlsMaxIter = 50, maxIter = 100, returnObject = TRUE)
  f <- tryCatch(suppressWarnings(nlme(fms[[kind]], data = d, fixed = fx, random = rd, method = if (reml) "REML" else "ML", control = ctl)), error = function(e) { message("nlme failed ", kind, ": ", conditionMessage(e)); NULL })
  if (is.null(f)) next
  r <- tryCatch(fixpoint(kind, d, rs, 0, as.numeric(fixef(f)), as.matrix(ranef(f))), error = function(e) { message("fixpoint failed ", kind, ": ", conditionMessage(e)); NULL })
  if (is.null(r) || !r$conv) { message("no convergence ", kind); next }
  # nlme's PNLS step re-estimates beta, b and D by ML whatever the method (nlme.c nlme_increment sets RML = 0); REML only rescales sigma, logLik and the se afterwards
  if (reml) { rss <- r$sigma^2 * r$nobs; r$val <- r$val + np / 2 * log(rss) - 0.5 * as.numeric(determinant(r$xvx)$modulus); r$nobs <- r$nobs - np; r$sigma <- sqrt(rss / r$nobs) }
  q <- length(rs); nobs <- r$nobs; ll <- r$val + nobs * (log(nobs) - (1 + log(2 * pi))) / 2
  npar <- np + q * (q + 1) / 2 + 1
  sd <- r$sigma * sqrt(diag(r$Dm)); cr <- cov2cor(r$Dm)[lower.tri(r$Dm)]; se <- r$sigma * sqrt(diag(solve(r$xvx)))
  ref <- c(as.numeric(fixef(f)), f$sigma, as.numeric(logLik(f)), sqrt(diag(pdMatrix(f$modelStruct$reStruct[[1]]))) * f$sigma)
  mine <- c(r$beta, r$sigma, ll, sd); if (abs(AIC(f) + 2 * as.numeric(logLik(f)) - 2 * npar) > 0 && abs(AIC(f) - (-2 * ll + 2 * npar)) > 1e-4 * abs(AIC(f))) { message("AIC differs"); next }
  if (max(abs(ref - mine) / pmax(abs(ref), 1e-3)) > 1e-5 || max(abs(sqrt(diag(vcov(f))) - se) / se) > 1e-4) { message("fixpoint differs from nlme ", kind, ": ", paste(signif(ref - mine, 3), collapse = " "), " se ", max(abs(sqrt(diag(vcov(f))) - se) / se)); next }
  ov <- c(r$beta, r$sigma, ll, -2 * ll + 2 * npar, -2 * ll + npar * log(nobs), sd, cr, se, as.vector(t(r$B[unique(as.integer(d$g)), , drop = FALSE])))
  args0 <- c(reml, nrow(d), cf[[4]], rep(cf[[5]], cf[[4]]), d$x, d$y, q, rs)
  for (j in seq_along(ov)) cases[[length(cases) + 1]] <- case("nlme", c(kind, j - 1, args0), ov[j], rel = 1e-7, abs = 1e-8)
}
emit("nlmenl", "nlme", list(cases))
