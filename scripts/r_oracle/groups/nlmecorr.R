# nlme::nlme with a correlation structure (correlation = corAR1(form = ~ 1 | g)) and/or a variance function (weights = varPower(form = ~ x)) for the
# within-group errors, self-start models, one grouping level, random effects on a subset of the parameters (full pdLogChol covariance), ML and REML.
# Reference and tolerances as in nlmenl.R: the fixed point of nlme's alternating algorithm (nlme_fixpoint.R with the error covariance Sfun: PNLS weights the
# residuals by its inverse, the ML step adds it to the random-effects part of V), checked against nlme(pnlsTol = 1e-7) before a case is kept.
# ML only: with a correlation or variance structure nlme's REML fit is not the ML fixed point rescaled (the correlation parameter moves, 0.762 to 0.772 in a probe), and
# nlme stops ~3e-5 from the REML fixed point (its PNLS step halves out), so REML with these structures is refused (nlme_fit_cv returns Singular), not checked.
# case: c(kind, q_out, reml, n, ng, gs[ng], x[n], y[n], nr, rset[nr], cor, var) with cor 1 = corAR1 and var 2 = varPower(~ x), 0 = none;
# output vector: fixed effects (np), sigma, logLik, AIC, BIC, random-effect sds (nr), their correlations (lower triangle by columns), standard errors of the fixed
# effects (np), ranef (group-major), then the AR1 phi if cor and the power delta if var.
suppressMessages(library(nlme))
suppressMessages(library(numDeriv))
cases <- list()
TOL <- 1e-8
set.seed(20261125)
source(file.path(root, "scripts", "r_oracle", "nlme_fixpoint.R"))
mkd <- function(kind, ng, m, cr, vr) {
  tru <- list(c(10, 6, 1.5), c(10, 2, -0.5), c(200, 0.1))[[kind]]
  xs <- list(seq(1, 12, length.out = m), seq(0.5, 8, length.out = m), seq(0.02, 1.1, length.out = m))[[kind]]
  sdr <- list(c(1.5, 0.6, 0.15), c(1, 0.5, 0.15), c(15, 0.03))[[kind]]; sde <- list(0.3, 0.2, 4)[[kind]]
  x <- rep(round(xs, 3), ng); g <- rep(seq_len(ng), each = m)
  RE <- matrix(rnorm(ng * length(tru)), ng, length(tru)) * rep(sdr, each = ng)
  e <- numeric(length(x))
  for (k in seq_len(ng)) { ix <- which(g == k); z <- rnorm(m); u <- numeric(m); u[1] <- z[1]; for (t in 2:m) u[t] <- cr * u[t - 1] + sqrt(1 - cr^2) * z[t]; e[ix] <- u }
  e <- e * sde * abs(x / mean(x))^vr
  y <- numeric(length(x))
  for (t in seq_along(x)) y[t] <- as.numeric(ssmod[[kind]](x[t], tru + RE[g[t], ])) + e[t]
  groupedData(y ~ x | g, data.frame(y = round(y, 4), x = x, g = factor(g)))
}
fms <- list(y ~ SSlogis(x, Asym, xmid, scal), y ~ SSasymp(x, Asym, R0, lrc), y ~ SSmicmen(x, Vm, K))
pn <- list(c("Asym", "xmid", "scal"), c("Asym", "R0", "lrc"), c("Vm", "K"))
# cfg: kind, rset, reml, groups, group size, cor (0/1), var (0/2), true AR1 phi, true power
cfgs <- list(list(1, 1, 0, 8, 9, 1, 0, 0.5, 0), list(1, 1, 0, 8, 9, 0, 2, 0, 0.6), list(1, 1, 0, 8, 9, 1, 2, 0.4, 0.5), list(1, c(1, 2), 0, 8, 9, 1, 2, 0.4, 0.5),
             list(3, 1, 0, 8, 9, 0, 2, 0, 0.5), list(2, 1, 0, 8, 9, 1, 0, 0.5, 0), list(3, 1, 0, 8, 9, 1, 2, 0.4, 0.5))
for (cf in cfgs) {
  kind <- cf[[1]]; rs <- cf[[2]]; reml <- cf[[3]]; ng <- cf[[4]]; m <- cf[[5]]; hc <- cf[[6]]; hv <- as.integer(cf[[7]] > 0)
  d <- mkd(kind, ng, m, cf[[8]], cf[[9]]); np <- length(pn[[kind]])
  fx <- as.formula(paste(paste(pn[[kind]], collapse = " + "), "~ 1")); rd <- as.formula(paste(paste(pn[[kind]][rs], collapse = " + "), "~ 1 | g"))
  ctl <- nlmeControl(pnlsTol = 1e-7, tolerance = 1e-9, msTol = 1e-12, pnlsMaxIter = 50, maxIter = 100, returnObject = TRUE)
  cor <- if (hc) corAR1(0.1, form = ~ 1 | g) else NULL; wt <- if (hv) varPower(form = ~ x) else NULL
  f <- tryCatch(suppressWarnings(nlme(fms[[kind]], data = d, fixed = fx, random = rd, correlation = cor, weights = wt, method = if (reml) "REML" else "ML", control = ctl)), error = function(e) { message("nlme failed ", kind, ": ", conditionMessage(e)); NULL })
  if (is.null(f)) next
  ncv <- hc + hv
  Sfun <- function(th) {
    Sf <- matrix(0, nrow(d), nrow(d)); gi <- as.integer(d$g); phi <- if (hc) tanh(th[1] / 2) else 0; dl <- if (hv) th[length(th)] else 0
    for (k in unique(gi)) { ix <- which(gi == k); mm <- length(ix); C <- phi^abs(outer(seq_len(mm), seq_len(mm), "-")); sdv <- abs(d$x[ix])^dl; Sf[ix, ix] <- sdv * C * rep(sdv, each = mm) }
    Sf
  }
  r <- tryCatch(fixpoint(kind, d, rs, 0, as.numeric(fixef(f)), as.matrix(ranef(f)), Sfun = Sfun, ncv = ncv), error = function(e) { message("fixpoint failed ", kind, ": ", conditionMessage(e)); NULL })
  if (is.null(r) || !r$conv) { message("no convergence ", kind); next }
  q <- length(rs); nobs <- r$nobs; ll <- r$val + nobs * (log(nobs) - (1 + log(2 * pi))) / 2
  npar <- np + q * (q + 1) / 2 + 1 + ncv
  sd <- r$sigma * sqrt(diag(r$Dm)); cr <- cov2cor(r$Dm)[lower.tri(r$Dm)]; se <- r$sigma * sqrt(diag(solve(r$xvx)))
  nth <- q * (q + 1) / 2; tcv <- r$th[nth + seq_len(ncv)]
  nat <- c(if (hc) tanh(tcv[1] / 2), if (hv) tcv[ncv])
  rn <- c(if (hc) as.numeric(coef(f$modelStruct$corStruct, unconstrained = FALSE)), if (hv) as.numeric(coef(f$modelStruct$varStruct, unconstrained = FALSE)))
  ref <- c(as.numeric(fixef(f)), f$sigma, as.numeric(logLik(f)), sqrt(diag(pdMatrix(f$modelStruct$reStruct[[1]]))) * f$sigma, rn)
  mine <- c(r$beta, r$sigma, ll, sd, nat)
  xtol <- if (reml) 1e-4 else 1e-5
  if (max(abs(ref - mine) / pmax(abs(ref), 1e-3)) > xtol || max(abs(sqrt(diag(vcov(f))) - se) / se) > 10 * xtol) { message("fixpoint differs from nlme ", kind, ": ", paste(signif(ref - mine, 3), collapse = " "), " se ", max(abs(sqrt(diag(vcov(f))) - se) / se)); next }
  message("cfg ", kind, " reml ", reml, " cor ", hc, " var ", hv, ": fixed point vs nlme ", signif(max(abs(ref - mine) / pmax(abs(ref), 1e-3)), 3), " nat ", paste(signif(nat, 5), collapse = " "))
  ov <- c(r$beta, r$sigma, ll, -2 * ll + 2 * npar, -2 * ll + npar * log(nobs), sd, cr, se, as.vector(t(r$B[unique(as.integer(d$g)), , drop = FALSE])), nat)
  args0 <- c(reml, nrow(d), ng, rep(m, ng), d$x, d$y, q, rs, hc, 2 * hv)
  for (j in seq_along(ov)) cases[[length(cases) + 1]] <- case("nlme", c(kind, j - 1, args0), ov[j], rel = TOL, abs = TOL)
  # nlme's own returned fixed effects, sigma, logLik and random-effect sds (pnlsTol = 1e-7 stopping point): the output index + 1000 selects them
  nref <- c(seq_len(np + 2) - 1, np + 4 + seq_len(q) - 1)
  for (j in seq_along(nref)) cases[[length(cases) + 1]] <- case("nlme", c(kind, 1000 + nref[j], args0), ref[j], rel = 2e-5, abs = 1e-6)
}
emit("nlmecorr", "nlme", list(cases))
