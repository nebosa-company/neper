# nlme::nlme with a numeric group-level covariate on parameters: fixed = list(p ~ z for the parameters in cm, p ~ 1 otherwise), self-start models, one
# grouping level, random effects on a subset of the parameters (full pdLogChol covariance), ML and REML. Reference and tolerances as in nlmenl.R (the fixed point
# of nlme's alternating algorithm, checked against nlme(pnlsTol = 1e-7)); fixpoint() builds the fixed design from fp (parameter of each coefficient) and Xf.
# case: c(kind, q_out, reml, n, ng, gs[ng], x[n], y[n], z[n], nr, rset[nr], cm[np]); output vector as in nlmenl.R with np replaced by the number of fixed coefficients.
suppressMessages(library(nlme))
suppressMessages(library(numDeriv))
cases <- list()
set.seed(20261123)
source(file.path(root, "scripts", "r_oracle", "nlme_fixpoint.R"))
mkd <- function(kind, ng, m, cm, gam) {
  tru <- list(c(10, 6, 1.5), c(10, 2, -0.5), c(200, 0.1), c(1, 9, 5, 1.2), c(8, 3, 0.7))[[kind]]
  xs <- list(seq(1, 12, length.out = m), seq(0.5, 8, length.out = m), seq(0.02, 1.1, length.out = m), seq(0, 10, length.out = m), seq(1, m * 2, length.out = m))[[kind]]
  sdr <- list(c(1.5, 0.6, 0.15), c(1, 0.5, 0.15), c(15, 0.03), c(0.5, 0.9, 0.4, 0.15), c(0.7, 0.3, 0.05))[[kind]]; sde <- list(0.3, 0.2, 4, 0.1, 0.15)[[kind]]
  x <- rep(round(xs, 3), ng); g <- rep(seq_len(ng), each = m)
  zg <- round(seq(-1, 1, length.out = ng)[sample.int(ng)], 3); z <- zg[g]
  RE <- matrix(rnorm(ng * length(tru)), ng, length(tru)) * rep(sdr, each = ng)
  y <- numeric(length(x))
  for (t in seq_along(x)) y[t] <- as.numeric(ssmod[[kind]](x[t], tru + cm * gam * z[t] + RE[g[t], ])) + rnorm(1, 0, sde)
  groupedData(y ~ x | g, data.frame(y = round(y, 4), x = x, g = factor(g), z = z))
}
fms <- list(y ~ SSlogis(x, Asym, xmid, scal), y ~ SSasymp(x, Asym, R0, lrc), y ~ SSmicmen(x, Vm, K), y ~ SSfpl(x, A, B, xmid, scal), y ~ SSgompertz(x, Asym, b2, b3))
pn <- list(c("Asym", "xmid", "scal"), c("Asym", "R0", "lrc"), c("Vm", "K"), c("A", "B", "xmid", "scal"), c("Asym", "b2", "b3"))
gamv <- list(c(1.2, 0.5, 0.15), c(1.2, 0.5, 0.15), c(20, 0.03), c(0.4, 0.5, 0.4, 0.1), c(0.8, 0.3, 0.05))
# cfg: kind, covariate parameters (1-based), rset, reml, groups, group size
cfgs <- list(list(1, c(1, 2), c(1, 2), 0, 10, 8), list(3, 1, 1, 0, 10, 7), list(4, 1, 1, 0, 10, 8), list(5, 1, 1, 0, 10, 9),
             list(1, c(1, 2), c(1, 2), 1, 10, 8), list(5, 3, c(1, 3), 1, 10, 9))
for (cf in cfgs) {
  kind <- cf[[1]]; cp <- cf[[2]]; rs <- cf[[3]]; reml <- cf[[4]]; npm <- length(pn[[kind]])
  cm <- as.numeric(seq_len(npm) %in% cp)
  d <- mkd(kind, cf[[5]], cf[[6]], cm, gamv[[kind]])
  fp <- integer(0); cols <- list()
  fxl <- list()
  for (j in seq_len(npm)) {
    fp <- c(fp, j); cols[[length(cols) + 1]] <- rep(1, nrow(d))
    if (cm[j] == 1) { fp <- c(fp, j); cols[[length(cols) + 1]] <- d$z; fxl[[j]] <- as.formula(paste(pn[[kind]][j], "~ z")) } else fxl[[j]] <- as.formula(paste(pn[[kind]][j], "~ 1"))
  }
  Xf <- do.call(cbind, cols); nf <- length(fp)
  rd <- as.formula(paste(paste(pn[[kind]][rs], collapse = " + "), "~ 1 | g"))
  ini <- coef(nls(fms[[kind]], d)); st <- unlist(lapply(seq_len(npm), function(j) if (cm[j] == 1) c(ini[j], 0) else ini[j]))
  ctl <- nlmeControl(pnlsTol = 1e-7, tolerance = 1e-9, msTol = 1e-12, pnlsMaxIter = 50, maxIter = 100, returnObject = TRUE)
  f <- tryCatch(suppressWarnings(nlme(fms[[kind]], data = d, fixed = fxl, random = rd, start = st, method = if (reml) "REML" else "ML", control = ctl)), error = function(e) { message("nlme failed ", kind, ": ", conditionMessage(e)); NULL })
  if (is.null(f)) next

  r <- tryCatch(fixpoint(kind, d, rs, 0, as.numeric(fixef(f)), as.matrix(ranef(f)), fp = fp, Xf = Xf), error = function(e) { message("fixpoint failed ", kind, ": ", conditionMessage(e), " ", paste(deparse(conditionCall(e)), collapse = "")); NULL })
  if (is.null(r) || !r$conv) { message("no convergence ", kind); next }
  r0 <- tryCatch(fixpoint(kind, d, rs, 0, as.numeric(st), NULL, fp = fp, Xf = Xf), error = function(e) NULL)
  message("cfg ", kind, " start-from-nls fixpoint ", if (is.null(r0)) "failed" else paste(r0$conv, signif(max(abs(r0$beta - r$beta) / pmax(abs(r$beta), 1e-3)), 3)))
  if (reml) { rss <- r$sigma^2 * r$nobs; r$val <- r$val + nf / 2 * log(rss) - 0.5 * as.numeric(determinant(r$xvx)$modulus); r$nobs <- r$nobs - nf; r$sigma <- sqrt(rss / r$nobs) }
  q <- length(rs); nobs <- r$nobs; ll <- r$val + nobs * (log(nobs) - (1 + log(2 * pi))) / 2
  npar <- nf + q * (q + 1) / 2 + 1
  sd <- r$sigma * sqrt(diag(r$Dm)); cr <- cov2cor(r$Dm)[lower.tri(r$Dm)]; se <- r$sigma * sqrt(diag(solve(r$xvx)))
  ref <- c(as.numeric(fixef(f)), f$sigma, as.numeric(logLik(f)), sqrt(diag(pdMatrix(f$modelStruct$reStruct[[1]]))) * f$sigma)
  mine <- c(r$beta, r$sigma, ll, sd)
  if (max(abs(ref - mine) / pmax(abs(ref), 1e-3)) > 1e-5 || max(abs(sqrt(diag(vcov(f))) - se) / se) > 1e-4) { message("fixpoint differs from nlme ", kind, ": ", paste(signif(ref - mine, 3), collapse = " "), " se ", max(abs(sqrt(diag(vcov(f))) - se) / se)); next }
  ov <- c(r$beta, r$sigma, ll, -2 * ll + 2 * npar, -2 * ll + npar * log(nobs), sd, cr, se, as.vector(t(r$B[unique(as.integer(d$g)), , drop = FALSE])))
  args0 <- c(reml, nrow(d), cf[[5]], rep(cf[[6]], cf[[5]]), d$x, d$y, d$z, q, rs, cm)
  # the correlation of the two random effects of the SSlogis fit is the least determined output (the D optimum is flat along it): the fixed point and Neper
  # land 1.5e-8 apart there (4.7e-8 relative), so correlations carry rel 1e-7 / abs 5e-8; everything else 1e-8
  for (j in seq_along(ov)) { icr <- (j - 1) >= nf + 4 + q && (j - 1) < nf + 4 + q + q * (q - 1) / 2
    cases[[length(cases) + 1]] <- case("nlme", c(kind, j - 1, args0), ov[j], rel = if (icr) 1e-7 else 1e-8, abs = if (icr) 5e-8 else 1e-8) }
  # nlme's own returned fixed effects, sigma, logLik and random-effect sds (pnlsTol = 1e-7 stopping point): the output index + 1000 selects them
  nref <- c(seq_len(nf + 2) - 1, nf + 4 + seq_len(q) - 1)
  for (j in seq_along(nref)) cases[[length(cases) + 1]] <- case("nlme", c(kind, 1000 + nref[j], args0), ref[j], rel = 2e-5, abs = 1e-6)
}
emit("nlmecov", "nlme", list(cases))
