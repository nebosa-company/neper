# nlme::gls with estimated correlation and variance structures, REML and ML, groups, anova and intervals.
# Case args: c(mode, q, spec [, spec2]); spec = c(reml, n, p, ck, nv, ng, gs[ng], t[n], y[n], X[n*p] column-major,
#   then per variance term c(kind, nstr, v[n])). mode 0: output q of the fit; mode 1: 2 (logLik1 - logLik2) (anova L.Ratio).
# Output vector: coef (p), sigma, logLik, AIC, BIC, natural correlation parameters, natural variance parameters, se (p), lower (p), upper (p).
# ck: 0 none, 1 AR1, 2 CompSymm, 3 CAR1, 4 ARMA(1,1), 6 Exp, 7 Gaus, 8 Spher, 9 Lin, 10 Ratio, 11 Symm.
# vk: 1 varIdent, 2 varPower, 3 varExp, 4 varConstPower, 5 varFixed.
# Tolerance rel 1e-6 / abs 1e-8: gls() runs nlminb at its default msTol 1e-5 on a forward-difference gradient, so its estimates sit ~1e-7 to 1e-6 from the
# optimum of the likelihood; the likelihood is flat there (logLik, AIC, BIC agree far tighter). Neper minimises to the exact optimum, so the reference
# cannot be reproduced closer than R's own stopping point without rebuilding every structure's objective on the R side (done for lme in nlmelist.R, not for gls).
suppressMessages(library(nlme))
cases <- list()
set.seed(20261120)
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
mkdata <- function(ck, ng, m, p) {
  n <- ng * m
  g <- rep(seq_len(ng), each = m)
  pos <- rep(seq_len(m), ng)
  tt <- if (ck %in% c(1, 4, 11)) pos else unlist(lapply(seq_len(ng), function(i) cumsum(round(runif(m, 0.6, 2), 2))))
  X <- cbind(1, matrix(round(rnorm(n * (p - 1)), 3), n, p - 1))
  v <- round(runif(n, 0.5, 3), 3)
  s <- letters[(pos - 1) %% 3 + 1]
  e <- unlist(lapply(seq_len(ng), function(i) as.numeric(arima.sim(list(ar = 0.5), m))))
  y <- round(drop(X %*% (1:p)) + e * exp(0.25 * v) + rnorm(ng)[g] * 0.5, 3)
  d <- data.frame(y = y, t = tt, g = factor(g), v = v, s = s)
  for (k in 2:p) d[[paste0("x", k)]] <- X[, k]
  list(d = d, X = X, n = n, ng = ng, m = m, p = p)
}
vstr <- function(vk, D) unlist(lapply(vk, function(k) {
  nstr <- if (k == 1) 3 else 0
  vv <- if (k == 1) as.numeric(factor(D$d$s, levels = unique(as.character(D$d$s))) ) - 1 else D$d$v
  c(k, nstr, vv)
}))
enc <- function(D, ck, vk, reml, pp = D$p, drop = 0) {
  X <- D$X[, seq_len(pp), drop = FALSE]
  c(reml, D$n, pp, ck, length(vk), D$ng, rep(D$m, D$ng), D$d$t, D$d$y, X, vstr(vk, D))
}
fitit <- function(D, ck, vk, reml, pp = D$p) {
  fm <- if (pp == 1) y ~ 1 else as.formula(paste("y ~", paste(paste0("x", 2:pp), collapse = " + ")))
  tryCatch(gls(fm, data = D$d, correlation = corf(ck), weights = varf(vk), method = if (reml) "REML" else "ML"), error = function(e) { message("skip ck=", ck, " vk=", paste(vk, collapse = ","), ": ", conditionMessage(e)); NULL })
}
outvec <- function(f, ck, vk, D) {
  cs <- f$modelStruct$corStruct
  cn <- if (ck == 0) numeric(0) else if (ck == 11) { mm <- corMatrix(cs)[[1]]; mm[lower.tri(mm)] } else as.numeric(coef(cs, unconstrained = FALSE))
  vs <- f$modelStruct$varStruct
  vn <- if (length(vk) == 0) numeric(0) else if (length(vk) == 1) as.numeric(unlist(coef(vs, unconstrained = FALSE))) else as.numeric(unlist(lapply(vs, function(z) unlist(coef(z, unconstrained = FALSE)))))
  iv <- intervals(f, which = "coef")$coef
  c(coef(f), f$sigma, as.numeric(logLik(f)), AIC(f), BIC(f), cn, vn, sqrt(diag(vcov(f))), iv[, 1], iv[, 3])
}
addcases <- function(args0, out, rel, abs) for (q in seq_along(out)) cases[[length(cases) + 1]] <<- case("gls", c(0, q - 1, args0), out[q], rel = rel, abs = abs)
vsets <- list(integer(0), 1, 2, 3, 4, 5, c(1, 2), c(1, 3))
cfg <- list()
for (ck in c(0, 1, 2, 3, 4, 6, 7, 8, 9, 10, 11)) for (vi in seq_along(vsets)) cfg[[length(cfg) + 1]] <- c(ck, vi)
for (ci in seq_along(cfg)) {
  ck <- cfg[[ci]][1]; vk <- vsets[[cfg[[ci]][2]]]
  # keep the grid small: every correlation kind with none/varIdent/varPower/varComb, the rest with AR1 and none
  if (ck != 1 && ck != 0 && !(length(vk) == 0 || identical(vk, 1) || identical(vk, 2) || identical(vk, c(1, 2)))) next
  if (ck == 0 && length(vk) == 0) next
  D <- if (ck == 11) mkdata(ck, 6, 4, 3) else mkdata(ck, 3, 8, 3)
  reml <- ci %% 2
  f <- fitit(D, ck, vk, reml)
  if (is.null(f)) next
  ov <- outvec(f, ck, vk, D)
  if (ci %% 3 != 0) ov <- ov[seq_len(length(ov) - 3 * D$p)]
  addcases(enc(D, ck, vk, reml), ov, 1e-6, 1e-8)
}
# anova between models: nested variance structure (ML), nested mean structure (ML), same fixed effects (REML)
for (rep in 1:3) {
  D <- mkdata(1, 3, 8, 3)
  for (spec in list(list(1, c(2), 1, integer(0), 3, 3, 0), list(1, c(3), 1, integer(0), 3, 3, 0), list(1, integer(0), 1, integer(0), 3, 2, 0), list(1, integer(0), 0, integer(0), 3, 3, 0), list(1, c(1), 1, integer(0), 3, 3, 1))) {
    ckA <- spec[[1]]; vkA <- spec[[2]]; ckB <- spec[[3]]; vkB <- spec[[4]]; ppA <- spec[[5]]; ppB <- spec[[6]]; reml <- spec[[7]]
    if (ckA == 0 && length(vkA) == 0) next
    fA <- fitit(D, ckA, vkA, reml, ppA); fB <- fitit(D, ckB, vkB, reml, ppB)
    if (is.null(fA) || is.null(fB)) next
    an <- anova(fB, fA)
    cases[[length(cases) + 1]] <- case("gls", c(1, 0, enc(D, ckA, vkA, reml, ppA), enc(D, ckB, vkB, reml, ppB)), an[["L.Ratio"]][2], rel = 1e-6, abs = 1e-8)
  }
}
emit("gls", "nlme", list(cases))
