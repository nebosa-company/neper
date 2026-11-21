# nlme::lme (random intercept or intercept + slope, with correlation and variance structures), lmList, and the nls self-start models.
# every case is c(family, ...): 1 lme, 2 lmlist, 3 ssval, 4 nls. lme args after the family: c(q_out, reml, n, p, ck, nv, ng, gs[ng], t[n], y[n], X[n*p] column-major, qz, Z[n*qz], then per variance term c(kind, nstr, v[n])).
#   Output vector: coef (p), sigma, logLik, AIC, BIC, random-effect sd (qz), random-effect correlations (lower triangle by columns),
#   natural correlation parameters, natural variance parameters, se (p), ranef (group-major).
# lmlist args: c(q_out, n, p, ng, gs[ng], y[n], X[n*p]); output per group: coef, sigma, se, lower, upper; then pooledSD.
# ssval args: c(kind, q_out, x, par...); output: value, gradient. nls args: c(kind, q_out, n, x[n], y[n]);
#   output: coef, sigma, deviance, logLik, AIC, BIC, se. kinds: 1 SSlogis, 2 SSasymp, 3 SSmicmen, 4 SSfpl, 5 SSgompertz.
# lme cases carry rel 5e-7 / abs 1e-8 (corSymm cases 1e-5 / 1e-6, compared on the identified outputs only). R's own lme stops ~1e-6 from the optimum (measured: Orthodont,
#   pdSymm + corAR1, only the start value of the AR1 parameter changed 0.05 / 0.2 / 0.4 -> estimates spread by 6e-6 relative; reruns with other
#   starts or tolerances differ that much), so the reference is lme's fit polished to the optimum of the same likelihood (see polished). lme output continues after ranef
#   (all groups) with the fixed-effect t limits (lower p, upper p) and the intervals.lme var-cov limits (natural scale: lower then upper; sds, re corr, cor, var, sigma);
#   the var-cov Hessian is Richardson-extrapolated (nlme's fdHess has ~1e-3 rounding noise), checked to 25% of lme's own apVar. Family 5: lme anova L.Ratio of two specs.
# nls cases carry rel 1e-6: the reference is nls restarted from the self-start fit at tol 1e-10 (1e-9 or 1e-8 where that does not converge).
suppressMessages(library(nlme))
cases <- list()
set.seed(20261121)
corf <- function(ck) switch(as.character(ck), "0" = NULL, "1" = corAR1(form = ~ t | g), "2" = corCompSymm(form = ~ 1 | g),
  "3" = corCAR1(form = ~ t | g), "4" = corARMA(form = ~ t | g, p = 1, q = 1), "6" = corExp(form = ~ t | g),
  "7" = corGaus(form = ~ t | g), "8" = corSpher(form = ~ t | g), "9" = corLin(form = ~ t | g), "10" = corRatio(form = ~ t | g),
  "11" = corSymm(form = ~ t | g))
varf <- function(vk) {
  one <- function(k) switch(as.character(k), "1" = varIdent(form = ~ 1 | s), "2" = varPower(form = ~ v), "3" = varExp(form = ~ v),
    "4" = varConstPower(form = ~ v), "5" = varFixed(~ v))
  if (length(vk) == 0) return(NULL)
  if (length(vk) == 1) return(one(vk))
  do.call(varComb, lapply(vk, one))
}
vstr <- function(vk, d) unlist(lapply(vk, function(k) {
  nstr <- if (k == 1) 3 else 0
  vv <- if (k == 1) as.numeric(factor(d$s)) - 1 else d$v
  c(k, nstr, vv)
}))
mkdata <- function(ng, m, p, qz, ck, bw = FALSE) {
  n <- ng * m
  g <- rep(seq_len(ng), each = m)
  pos <- rep(seq_len(m), ng)
  tt <- if (ck %in% c(1, 4, 11)) pos else unlist(lapply(seq_len(ng), function(i) cumsum(round(runif(m, 0.6, 2), 2))))
  X <- cbind(1, matrix(round(rnorm(n * (p - 1)), 3), n, p - 1))
  if (bw) X[, p] <- round(rnorm(ng), 3)[g]
  v <- round(runif(n, 0.5, 3), 3)
  s <- letters[(pos - 1) %% 3 + 1]
  b0 <- rnorm(ng, 0, 2.5)[g]
  b1 <- rnorm(ng, 0, 2)[g]
  e <- unlist(lapply(seq_len(ng), function(i) as.numeric(arima.sim(list(ar = 0.4), m))))
  y <- round(drop(X %*% (1:p)) + b0 + (if (qz == 2) b1 * X[, 2] else 0) + e * exp(0.15 * v), 3)
  d <- data.frame(y = y, t = tt, g = factor(g), v = v, s = s)
  for (k in 2:p) d[[paste0("x", k)]] <- X[, k]
  list(d = d, X = X, n = n, ng = ng, m = m, p = p, qz = qz)
}
ctl <- lmeControl(opt = "nlminb", msTol = 1e-12, tolerance = 1e-10, msMaxIter = 500, msMaxEval = 1000, maxIter = 200, niterEM = 25, returnObject = FALSE, x.tol = 1e-11, xf.tol = 1e-11)
fitlme <- function(D, ck, vk, reml) {
  fx <- as.formula(paste("y ~", paste(paste0("x", 2:D$p), collapse = " + ")))
  rd <- if (D$qz == 2) ~ x2 | g else ~ 1 | g
  tryCatch(lme(fx, data = D$d, random = rd, correlation = corf(ck), weights = varf(vk), method = if (reml) "REML" else "ML", control = ctl),
    error = function(e) { message("skip ck=", ck, " vk=", paste(vk, collapse = ","), " q=", D$qz, " ", reml, ": ", conditionMessage(e)); NULL })
}
outlme <- function(f, ck, vk, D) {
  cs <- f$modelStruct$corStruct
  cn <- if (ck == 0) numeric(0) else if (ck == 11) { mm <- corMatrix(cs)[[1]]; mm[lower.tri(mm)] } else as.numeric(coef(cs, unconstrained = FALSE))
  vs <- f$modelStruct$varStruct
  vn <- if (length(vk) == 0) numeric(0) else if (length(vk) == 1) as.numeric(unlist(coef(vs, unconstrained = FALSE))) else as.numeric(unlist(lapply(vs, function(z) unlist(coef(z, unconstrained = FALSE)))))
  vc <- getVarCov(f)
  sds <- sqrt(diag(vc))
  rc <- cov2cor(vc)[lower.tri(vc)]
  c(fixef(f), f$sigma, as.numeric(logLik(f)), AIC(f), BIC(f), sds, rc, cn, vn, sqrt(diag(vcov(f))), as.numeric(t(as.matrix(ranef(f))))[1:(3 * D$qz)])
}
# R's lme stops about 1e-6 from the optimum (a rerun with other starting values or tolerances moves the estimates that far), so the
# reference is lme's own fit polished to the optimum of the same likelihood: the objective is rebuilt from the fitted structures
# (reStruct, corMatrix, varWeights), checked equal to logLik(f) at lme's estimates, then minimised by Newton steps with Richardson
# derivatives; outputs are recomputed at the polished parameters.
polished <- function(f, ck, vk, D, reml) {
  ms <- f$modelStruct; p0 <- as.numeric(coef(ms)); n <- D$n; X <- D$X; y <- D$d$y; qz <- D$qz; px <- D$p
  Z <- if (qz == 2) cbind(1, X[, 2]) else matrix(1, n, 1)
  gi <- split(seq_len(n), rep(seq_len(D$ng), each = D$m))
  nobs <- n - reml * px
  parts <- function(p, Dov = NULL) {
    coef(ms) <- p
    Dm <- if (is.null(Dov)) as.matrix(ms$reStruct)[[1]] else Dov
    Cl <- if (ck == 0) NULL else corMatrix(ms$corStruct)
    w <- if (length(vk) == 0) rep(1, n) else as.numeric(varWeights(ms$varStruct))
    Vi <- lapply(seq_along(gi), function(k) {
      ix <- gi[[k]]
      C <- if (is.null(Cl)) diag(length(ix)) else { cc <- Cl[[k]]; cc }
      L <- C / outer(w[ix], w[ix])
      L + Z[ix, , drop = FALSE] %*% Dm %*% t(Z[ix, , drop = FALSE])
    })
    list(Dm = Dm, Vi = Vi)
  }
  core <- function(p, Dov = NULL) {
    pr <- parts(p, Dov); xvx <- matrix(0, px, px); xvy <- numeric(px); ld <- 0
    for (k in seq_along(gi)) { ix <- gi[[k]]; Vinv <- solve(pr$Vi[[k]]); xvx <- xvx + t(X[ix, ]) %*% Vinv %*% X[ix, ]; xvy <- xvy + t(X[ix, ]) %*% Vinv %*% y[ix]; ld <- ld + determinant(pr$Vi[[k]])$modulus }
    beta <- solve(xvx, xvy); rss <- 0
    for (k in seq_along(gi)) { ix <- gi[[k]]; r <- y[ix] - X[ix, ] %*% beta; rss <- rss + drop(t(r) %*% solve(pr$Vi[[k]]) %*% r) }
    list(pr = pr, xvx = xvx, beta = beta, rss = rss, val = -nobs / 2 * log(rss) - ld / 2 - reml / 2 * as.numeric(determinant(xvx)$modulus))
  }
  obj <- function(p) -core(p)$val
  const <- as.numeric(logLik(f)) - core(p0)$val
  if (abs(const) > 1e5) stop("objective mismatch")
  p <- p0
  for (it in 1:30) {
    gr <- numDeriv::grad(obj, p, method = "Richardson"); H <- numDeriv::hessian(obj, p, method = "Richardson")
    st <- tryCatch(solve(H, gr), error = function(e) NULL)
    if (is.null(st)) break
    pn <- p - st; if (obj(pn) > obj(p) + 1e-13) break
    p <- pn; if (max(abs(st)) < 1e-12) break
  }
  # lme's estimates must reproduce lme's own outputs through this objective
  c0 <- core(p0); sg0 <- sqrt(c0$rss / nobs)
  if (abs(sg0 - f$sigma) > 1e-8 * f$sigma || max(abs(c0$beta - fixef(f))) > 1e-8) stop("objective differs from lme at its own estimates")
  cr <- core(p); coef(ms) <- p
  sg <- sqrt(cr$rss / nobs); ll <- cr$val + const
  npar <- px + length(p) + 1
  Dm <- cr$pr$Dm; vc <- sg^2 * Dm
  cs <- ms$corStruct; vs <- ms$varStruct
  cn <- if (ck == 0) numeric(0) else as.numeric(coef(cs, unconstrained = FALSE))
  vn <- if (length(vk) == 0) numeric(0) else if (length(vk) == 1) as.numeric(unlist(coef(vs, unconstrained = FALSE))) else as.numeric(unlist(lapply(vs, function(z) unlist(coef(z, unconstrained = FALSE)))))
  b <- unlist(lapply(seq_along(gi), function(k) { ix <- gi[[k]]; drop(Dm %*% t(Z[ix, , drop = FALSE]) %*% solve(cr$pr$Vi[[k]], y[ix] - X[ix, ] %*% cr$beta)) }))
  # approximate variance-covariance (lmeApVar): the full likelihood in log sd / correlation-logit, cor, var and log sigma parameters,
  # nlme's fdHess at minAbsPar 0.05; first checked against lme's own apVar at lme's estimates
  nr <- qz * (qz + 1) / 2
  tonat <- function(Dm, sig, pcv) c(if (qz == 1) log(sig * sqrt(Dm[1, 1])) else c(log(sig * sqrt(diag(Dm))), { r <- Dm[1, 2] / sqrt(Dm[1, 1] * Dm[2, 2]); log((1 + r) / (1 - r)) }), pcv, log(sig))
  llfull <- function(th) {
    sig <- exp(th[length(th)])
    Sb <- if (qz == 1) matrix(exp(2 * th[1]), 1, 1) else { s <- exp(th[1:2]); r <- (exp(th[3]) - 1) / (exp(th[3]) + 1); matrix(c(s[1]^2, r * s[1] * s[2], r * s[1] * s[2], s[2]^2), 2, 2) }
    cc <- core(c(rep(0, nr), th[nr + seq_len(length(th) - nr - 1)]), Sb / sig^2)
    ld <- 0; for (k in seq_along(gi)) ld <- ld + as.numeric(determinant(cc$pr$Vi[[k]])$modulus)
    -nobs / 2 * log(2 * pi * sig^2) - ld / 2 - reml / 2 * as.numeric(determinant(cc$xvx)$modulus) - cc$rss / (2 * sig^2)
  }
  # Hessian by three-level Richardson extrapolation of central differences (steps h, h/2, h/4 with h = 0.02 (1 + |x|)): nlme's fdHess carries ~1e-3 rounding noise
  hessR <- function(fn, x) {
    P <- length(x); hh <- 0.02 * (1 + abs(x)); f0 <- fn(x)
    lev <- function(s) {
      h <- hh / 2^s; D <- matrix(0, P, P)
      for (i in 1:P) { e <- numeric(P); e[i] <- h[i]; D[i, i] <- (fn(x + e) - 2 * f0 + fn(x - e)) / h[i]^2 }
      for (i in seq_len(P - 1)) for (j in (i + 1):P) { ei <- numeric(P); ei[i] <- h[i]; ej <- numeric(P); ej[j] <- h[j]; D[i, j] <- D[j, i] <- (fn(x + ei + ej) - fn(x + ei - ej) - fn(x - ei + ej) + fn(x - ei - ej)) / (4 * h[i] * h[j]) }
      D
    }
    D0 <- lev(0); D1 <- lev(1); D2 <- lev(2)
    (16 * (4 * D2 - D1) / 3 - (4 * D1 - D0) / 3) / 15
  }
  apv <- function(th) { H <- hessR(llfull, th); if (!all(eigen(H, only.values = TRUE)$values < 0)) stop("apVar not positive definite"); solve(-H) }
  sg0b <- sg0; Dm0 <- c0$pr$Dm
  th0 <- tonat(Dm0, sg0b, p0[-seq_len(nr)])
  okiv <- !is.character(f$apVar) && tryCatch(max(abs(th0 - attr(f$apVar, "Pars"))) < 1e-6 && max(abs(apv(th0) - f$apVar)) < 0.25 * max(abs(f$apVar)) && max(abs(hessR(llfull, th0) - numDeriv::hessian(llfull, th0))) < 1e-5 * max(abs(hessR(llfull, th0))), error = function(e) FALSE)
  ths <- tonat(Dm, sg, p[-seq_len(nr)])
  aV <- if (okiv) tryCatch(apv(ths), error = function(e) NULL) else NULL; if (is.null(aV)) okiv <- FALSE; len <- if (okiv) qnorm(0.975) * sqrt(diag(aV)) else 0
  natv <- function(th) {
    coef(ms) <- c(rep(0, nr), th[nr + seq_len(length(th) - nr - 1)])
    cs2 <- ms$corStruct; vs2 <- ms$varStruct
    cn2 <- if (ck == 0) numeric(0) else as.numeric(coef(cs2, unconstrained = FALSE))
    vn2 <- if (length(vk) == 0) numeric(0) else if (length(vk) == 1) as.numeric(unlist(coef(vs2, unconstrained = FALSE))) else as.numeric(unlist(lapply(vs2, function(z) unlist(coef(z, unconstrained = FALSE)))))
    c(exp(th[1:qz]), if (qz == 2) (exp(th[3]) - 1) / (exp(th[3]) + 1), cn2, vn2, exp(th[length(th)]))
  }
  fx <- sg * sqrt(diag(solve(cr$xvx))); tq <- qt(0.975, f$fixDF$X)
  base <- c(cr$beta, sg, ll, -2 * ll + 2 * npar, -2 * ll + npar * log(nobs), sqrt(diag(vc)), cov2cor(vc)[lower.tri(vc)], cn, vn, sg * sqrt(diag(solve(cr$xvx))), b)
  if (!okiv) { message("no apVar intervals ck=", ck, " vk=", paste(vk, collapse = ","), " chr=", is.character(f$apVar), " dpar=", if (is.character(f$apVar)) NA else max(abs(th0 - attr(f$apVar, "Pars"))), " dH=", if (is.character(f$apVar)) NA else tryCatch(max(abs(apv(th0) - f$apVar)) / max(abs(f$apVar)), error = function(e) "npd")); return(base) }
  c(base, cr$beta - tq * fx, cr$beta + tq * fx, natv(ths - len), natv(ths + len))
}
# cfg: list(q random effects, correlation kind, variance kinds, reml, group size)
cfgs <- list(
  list(1, 0, integer(0), 1, 7), list(1, 0, integer(0), 0, 7), list(2, 0, integer(0), 1, 7), list(2, 0, integer(0), 0, 7),
  list(1, 1, integer(0), 1, 7), list(1, 3, integer(0), 0, 7), list(1, 0, 2, 1, 7), list(1, 0, 1, 0, 7), list(2, 0, 3, 1, 7), list(1, 1, 2, 1, 7),
  list(1, 4, integer(0), 1, 7), list(1, 7, integer(0), 0, 7), list(1, 8, integer(0), 1, 7), list(1, 9, integer(0), 1, 7),
  list(1, 10, integer(0), 1, 7), list(1, 11, integer(0), 0, 4), list(1, 11, integer(0), 1, 4), list(2, 10, integer(0), 1, 7),
  list(1, 0, 5, 1, 7), list(1, 0, 4, 0, 7), list(2, 0, 5, 0, 7), list(1, 1, 5, 1, 7), list(1, 6, c(5, 3), 1, 7), list(1, 0, integer(0), 1, 7, 1), list(1, 3, 2, 0, 7, 1))
ci <- 0; firsthalf <- NULL
for (cf in cfgs) {
  ci <- ci + 1
  if (ci == 14) { firsthalf <- cases; cases <- list() }
  qz <- cf[[1]]; ck <- cf[[2]]; vk <- cf[[3]]; reml <- cf[[4]]
  D <- mkdata(if (cf[[5]] == 4) 8 else 6, cf[[5]], 3, qz, ck, length(cf) >= 6)
  f <- fitlme(D, ck, vk, reml)
  if (is.null(f)) next
  Z <- if (qz == 2) cbind(1, D$X[, 2]) else matrix(1, D$n, 1)
  args0 <- c(reml, D$n, D$p, ck, length(vk), D$ng, rep(D$m, D$ng), D$d$t, D$d$y, D$X, qz, Z, vstr(vk, D$d))
  ov <- if (ck == 11) outlme(f, ck, vk, D) else polished(f, ck, vk, D, reml)
  # corSymm next to a random intercept is not identified: only the fixed effects, logLik, AIC, BIC and se are compared
  keep <- if (ck == 11) c(1:D$p, D$p + 2:4, seq(length(ov) - 3 * D$qz - D$p + 1, length.out = D$p)) else seq_along(ov)
  tl <- if (ck == 11) c(1e-5, 1e-6) else c(5e-7, 1e-8)
  for (q in keep) cases[[length(cases) + 1]] <- case("nl", c(1, q - 1, args0), ov[q], rel = tl[1], abs = tl[2])
}
# anova between lme models: 2 (logLik A - logLik B) of nested pairs, case args c(5, 0, spec A, spec B) with the lme spec layout above
mkargs <- function(D, qz, ck, vk, reml) {
  Z <- if (qz == 2) cbind(1, D$X[, 2]) else matrix(1, D$n, 1)
  c(reml, D$n, D$p, ck, length(vk), D$ng, rep(D$m, D$ng), D$d$t, D$d$y, D$X, qz, Z, vstr(vk, D$d))
}
withp <- function(D, p, qz) { D$p <- p; D$X <- D$X[, 1:p, drop = FALSE]; D$qz <- qz; D }
# pair: data random effects, A (q, ck, vk, p), B (q, ck, vk, p), reml
prs <- list(
  list(1, list(1, 1, integer(0), 3), list(1, 0, integer(0), 3), 1), list(1, list(1, 0, 2, 3), list(1, 0, integer(0), 3), 0),
  list(2, list(2, 0, integer(0), 3), list(1, 0, integer(0), 3), 0), list(1, list(1, 0, integer(0), 3), list(1, 0, integer(0), 2), 0),
  list(1, list(1, 3, integer(0), 3), list(1, 0, integer(0), 3), 1), list(1, list(1, 0, 1, 3), list(1, 0, integer(0), 3), 1))
for (pr in prs) {
  A <- pr[[2]]; B <- pr[[3]]; reml <- pr[[4]]
  D0 <- mkdata(6, 7, 3, pr[[1]], A[[2]])
  DA <- withp(D0, A[[4]], A[[1]]); DB <- withp(D0, B[[4]], B[[1]])
  fA <- fitlme(DA, A[[2]], A[[3]], reml); fB <- fitlme(DB, B[[2]], B[[3]], reml)
  if (is.null(fA) || is.null(fB)) next
  lr <- 2 * (polished(fA, A[[2]], A[[3]], DA, reml)[DA$p + 2] - polished(fB, B[[2]], B[[3]], DB, reml)[DB$p + 2])
  lr0 <- anova(fB, fA)[["L.Ratio"]][2]
  if (abs(lr - lr0) > 1e-5 * abs(lr0) + 1e-6) { message("anova pair differs from nlme: ", lr, " ", lr0); next }
  cases[[length(cases) + 1]] <- case("nl", c(5, 0, mkargs(DA, A[[1]], A[[2]], A[[3]], reml), mkargs(DB, B[[1]], B[[2]], B[[3]], reml)), lr, rel = 5e-7, abs = 1e-8)
}
# lmList, self-starts and nls go to nlmenls.json (the lme cases above are nlmelist.json: one file would pass the 2 MB cap)
lmecases <- cases; cases <- list()
for (rep in 1:2) {
  ng <- 5; m <- 6 + rep; p <- 3; n <- ng * m
  g <- rep(seq_len(ng), each = m)
  X <- cbind(1, matrix(round(rnorm(n * (p - 1)), 3), n, p - 1))
  y <- round(drop(X %*% c(2, -1, 0.5)) + rnorm(ng)[g] + rnorm(n), 3)
  d <- data.frame(y = y, g = factor(g), x2 = X[, 2], x3 = X[, 3])
  l <- lmList(y ~ x2 + x3 | g, data = d)
  gl <- lapply(l, function(z) { s <- summary(z); ci <- confint(z); c(coef(z), s$sigma, s$coefficients[, 2], ci[, 1], ci[, 2]) })
  ov <- c(unlist(gl), pooledSD(l))
  for (q in seq_along(ov)) cases[[length(cases) + 1]] <- case("nl", c(2, q - 1, n, p, ng, rep(m, ng), y, X), ov[q], rel = 1e-9, abs = 1e-10)
}
# self-start model values and gradients
# the gradient attribute exists only when the parameter arguments are bare names
ssf <- list(function(x, p) { Asym <- p[1]; xmid <- p[2]; scal <- p[3]; SSlogis(x, Asym, xmid, scal) }, function(x, p) { Asym <- p[1]; R0 <- p[2]; lrc <- p[3]; SSasymp(x, Asym, R0, lrc) },
  function(x, p) { Vm <- p[1]; K <- p[2]; SSmicmen(x, Vm, K) }, function(x, p) { A <- p[1]; B <- p[2]; xmid <- p[3]; scal <- p[4]; SSfpl(x, A, B, xmid, scal) },
  function(x, p) { Asym <- p[1]; b2 <- p[2]; b3 <- p[3]; SSgompertz(x, Asym, b2, b3) })
pars <- list(list(c(10, 6, 1.5), c(3.2, -0.7, 0.9)), list(c(10, 2, -0.5), c(4, 7, 0.3)), list(c(200, 0.1), c(2.5, 1.7)),
  list(c(1, 9, 5, 1.2), c(-2, 3, 0.5, 2.1)), list(c(8, 3, 0.7), c(2, 0.4, 1.3)))
for (kd in 1:5) for (pr in pars[[kd]]) for (x in c(0.2, 1, 2.5, 4.75, 8)) {
  v <- ssf[[kd]](x, pr)
  ov <- c(as.numeric(v), as.numeric(attr(v, "gradient")))
  for (q in seq_along(ov)) cases[[length(cases) + 1]] <- case("nl", c(3, kd, q - 1, x, pr), ov[q], rel = 1e-12, abs = 1e-14)
}
# nls fits of the self-start models
mk <- list(
  function() { x <- round(seq(1, 12, length.out = 14) + runif(14, -0.2, 0.2), 3); list(x = x, y = round(10 / (1 + exp((6 - x) / 1.5)) + rnorm(14, 0, 0.2), 3)) },
  function() { x <- round(seq(0.5, 8, length.out = 12) + runif(12, -0.1, 0.1), 3); list(x = x, y = round(10 + (2 - 10) * exp(-exp(-0.5) * x) + rnorm(12, 0, 0.15), 3)) },
  function() { x <- round(c(0.02, 0.06, 0.11, 0.22, 0.56, 1.1) * rep(1, 6) * runif(6, 0.9, 1.1), 3); list(x = x, y = round(200 * x / (0.1 + x) + rnorm(6, 0, 4), 2)) },
  function() { x <- round(seq(0, 10, length.out = 15) + runif(15, -0.2, 0.2), 3); list(x = x, y = round(1 + 8 / (1 + exp((5 - x) / 1.2)) + rnorm(15, 0, 0.15), 3)) },
  function() { x <- 1:14; list(x = x, y = round(8 * exp(-3 * 0.7^x) + rnorm(14, 0, 0.1), 3)) })
# selfStart fit, then restarted from it at tol 1e-10 (the self-start alone stops at nls's default relative offset 1e-5)
fms <- list(y ~ SSlogis(x, Asym, xmid, scal), y ~ SSasymp(x, Asym, R0, lrc), y ~ SSmicmen(x, Vm, K), y ~ SSfpl(x, A, B, xmid, scal),
  y ~ SSgompertz(x, Asym, b2, b3))
nlsf <- lapply(fms, function(fm) function(d) {
  f0 <- nls(fm, d)
  for (tl in c(1e-10, 1e-9, 1e-8)) { f <- try(nls(fm, d, start = coef(f0), control = nls.control(tol = tl, minFactor = 1e-14, maxiter = 200)), silent = TRUE); if (!inherits(f, "try-error")) return(f) }
  stop("no convergence") })
for (kd in 1:5) for (rep in 1:3) {
  d <- as.data.frame(mk[[kd]]())
  f <- tryCatch(nlsf[[kd]](d), error = function(e) { message("skip nls ", kd, ": ", conditionMessage(e)); NULL })
  if (is.null(f)) next
  ov <- c(coef(f), sigma(f), deviance(f), as.numeric(logLik(f)), AIC(f), BIC(f), summary(f)$coefficients[, 2])
  for (q in seq_along(ov)) cases[[length(cases) + 1]] <- case("nl", c(4, kd, q - 1, nrow(d), d$x, d$y), ov[q], rel = 1e-6, abs = 1e-8)
}
emit("nlmelist", "nlme", list(firsthalf))
emit("nlmelist2", "nlme", list(lmecases))
emit("nlmenls", "nlme", list(cases))
