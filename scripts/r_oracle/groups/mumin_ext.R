# MuMIn beyond the plain lm/glm: prior weights, offsets, aliased designs, negative binomial (fixed theta and glm.nb), quasi families, dredge `varying`, subset expressions,
# and r.squaredGLMM of mixed models from their fitted pieces.
#   model args: (n, nt, fam, rank, chat, beta, mlo, mhi, fixed, cutoff, level, hasw, haso, theta, nopts, ndim, naltw, nalto, nrules, n2, nextra,
#     then parents x nt, extra kinds x nextra, options x 5 (dim, kind, fam, theta, arr), wt x n if hasw, off x n if haso, alt weights x (naltw n), alt offsets x (nalto n),
#     y x n, term columns x (n nt), new rows x (n2 nt), new offset x n2 if haso); the case input is (subset expression, term names)
#   fam: 200 lm, 0 gaussian, 1 binomial, 2 poisson, 3 Gamma inverse, 4 Gamma log, 5 gaussian log, 6 probit, 7 cloglog, 8 inverse.gaussian log, 9 negative.binomial(theta), 10 glm.nb,
#     201 quasipoisson, 202 quasibinomial. Every case answers one quantity as sum(v * seq_along(v)), NA as 0.
suppressMessages(library(MuMIn)); suppressMessages(library(MASS)); suppressMessages(library(lme4))
options(na.action = "na.fail")
cases <- list()
addc <- function(fn, args, want, input = NULL, rel = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-10, input = input)
S <- function(v) { v <- as.numeric(v); v[is.na(v)] <- 0; sum(v * seq_along(v)) }
famobj <- function(code, theta = 1) switch(as.character(code), "0" = gaussian(), "1" = binomial(), "2" = poisson(), "3" = Gamma(), "4" = Gamma("log"), "5" = gaussian("log"),
  "6" = binomial("probit"), "7" = binomial("cloglog"), "8" = inverse.gaussian("log"), "9" = negative.binomial(theta), "201" = quasipoisson(), "202" = quasibinomial())
rk <- c("AICc", "AIC", "BIC", "QAIC", "QAICc", "Cp")
rd <- function(x) round(x, 3)
fitm <- function(f, d, fam, theta, hasw, haso) {
  if (fam == 200) { cl <- list(as.name("lm"), formula = f, data = quote(d)) }
  else if (fam == 10) { cl <- list(quote(MASS::glm.nb), formula = f, data = quote(d)) }
  else cl <- list(as.name("glm"), formula = f, family = famobj(fam, theta), data = quote(d))
  if (hasw) cl$weights <- quote(w)
  if (haso) cl$offset <- quote(off)
  tryCatch(eval(as.call(cl)), error = function(e) stop(paste("fitm fam", fam, hasw, haso, conditionMessage(e))))
}
gen <- function(fam, n, binw = FALSE) {
  a <- rd(runif(n, -1, 1)); b <- rd(runif(n, -1, 1)); c <- rd(runif(n, -1, 1)); d <- rd(runif(n, -1, 1))
  w <- round(runif(n, 0.5, 2), 2); off <- rd(runif(n, -0.5, 0.5)); e <- rd(a + b)
  eta <- 0.3 + 0.6 * a - 0.5 * b + 0.3 * c
  y <- switch(as.character(fam), "200" = , "0" = eta + rnorm(n, 0, 0.5), "1" = , "202" = rbinom(n, 1, plogis(eta)), "6" = rbinom(n, 1, pnorm(eta)), "7" = rbinom(n, 1, 1 - exp(-exp(eta - 0.4))),
    "2" = , "201" = rpois(n, exp(eta + off)), "3" = rgamma(n, 4, 4 * (2 + 0.6 * a - 0.5 * b + 0.3 * c)), "4" = rgamma(n, 4, 4 / exp(eta)), "5" = exp(eta + rnorm(n, 0, 0.2)),
    "8" = exp(eta) * rgamma(n, 30, 30), "9" = , "10" = rnbinom(n, mu = exp(eta + off), size = 2))
  if (binw) { w <- sample(2:8, n, TRUE); y <- rbinom(n, w, plogis(eta)) / w }
  y <- if (fam %in% c(1, 6, 7, 202, 2, 201, 9, 10) && !binw) y else if (binw) y else rd(y)
  y <- if (fam %in% c(3, 4, 5, 8)) pmax(y, 0.01) else y
  data.frame(y = y, a = a, b = b, c = c, d = d, e = e, w = w, off = off)
}
scenario <- function(fam, rank = 0, chat = 1, beta = 0, tn = c("a", "b", "c", "d"), hasw = FALSE, haso = FALSE, theta = 2, binw = FALSE, expr = "", fixed = character(), mlim = NULL,
                     varying = NULL, vopts = NULL, extra = NULL, extrak = integer(), n = 30, deep = FALSE, gcases = FALSE, byid = FALSE) {
  d <- gen(fam, n, binw); nt <- length(tn); bit <- function(z) 2^(match(z, tn) - 1)
  frm <- as.formula(paste("y ~", paste(tn, collapse = " + ")))
  gm <- fitm(frm, d, fam, theta, hasw, haso)
  XX <- sapply(tn, function(z) d[[z]])
  nd <- data.frame(a = rd(runif(5, -1, 1)), b = rd(runif(5, -1, 1)), c = rd(runif(5, -1, 1)), d = rd(runif(5, -1, 1)), off = rd(runif(5, -0.5, 0.5))); nd$e <- rd(nd$a + nd$b)
  XN <- sapply(tn, function(z) nd[[z]])
  fixedmask <- sum(unlist(lapply(fixed, bit))); ml <- if (is.null(mlim)) c(0, nt) else mlim
  args <- list(gm, beta = c("none", "sd", "partial.sd")[beta + 1], fixed = if (length(fixed)) fixed else NULL, m.lim = mlim, extra = extra, trace = FALSE)
  if (rank == 3 || rank == 4) args <- c(args, list(rank = rk[rank + 1], chat = chat)) else if (rank != 0) args$rank <- rk[rank + 1]
  if (nzchar(expr)) args$subset <- parse(text = expr)
  if (!is.null(varying)) args$varying <- varying
  dr <- do.call(dredge, args)
  nm <- nrow(dr); cutoff <- dr$delta[min(5, nm)] + 1e-6
  tnall <- c("(Intercept)", tn); nopts <- if (is.null(vopts)) 0 else nrow(vopts); ndim <- if (is.null(vopts)) 0 else max(vopts[, 1]) + 1
  parents <- rep(0, nt)
  cfg <- function() c(n, nt, fam, rank, chat, beta, ml[1], ml[2], fixedmask, cutoff, 0.9, hasw, haso, theta, nopts, ndim, as.numeric(!is.null(varying) && any(vopts[, 2] == 2)), as.numeric(!is.null(varying) && any(vopts[, 2] == 3)), as.numeric(byid), 5, length(extrak),
    parents, extrak, if (nopts) as.vector(t(vopts)), if (hasw) d$w, if (haso) d$off, if (!is.null(varying) && any(vopts[, 2] == 2)) d$w, if (!is.null(varying) && any(vopts[, 2] == 3)) d$off, d$y, as.vector(XX), as.vector(XN), if (haso) nd$off)
  a0 <- cfg(); inp <- c(expr, tn)
  est <- as.matrix(dr[, tnall]); est[] <- as.numeric(est); cts <- attr(dr, "coefTables"); sem <- cdf <- est; sem[] <- NA; cdf[] <- NA
  for (i in seq_len(nm)) { ct <- cts[[i]]; rn <- MuMIn:::fixCoefNames(rownames(ct)); sem[i, rn] <- ct[, 2] }
  if (byid) { o <- order(as.numeric(rownames(dr))); dr <- dr[o, ]; est <- est[o, , drop = FALSE]; sem <- sem[o, , drop = FALSE] }
  add <- function(f, v) addc(f, a0, v, inp)
  add("t_id", S(as.numeric(rownames(dr)))); add("t_df", S(dr$df)); add("t_ll", S(dr[[ncol(dr) - 3]])); add("t_ic", S(dr[[ncol(dr) - 2]])); add("t_delta", S(dr$delta)); add("t_weight", S(dr$weight))
  add("t_est", S(est)); add("t_se", S(sem))
  if (fam == 10) for (j in seq_len(ncol(est))) add(paste0("t_col", j - 1), S(est[, j]))
  for (k in seq_len(ndim)) add(paste0("v_", k), S(as.integer(dr[[colnames(dr)[nt + 1 + k]]])))
  for (k in seq_along(extrak)) add(paste0("t_ex", k), S(dr[[colnames(dr)[nt + 1 + ndim + k]]]))
  if (deep) {
    ma <- eval(bquote(model.avg(dr, subset = delta < .(cutoff)))); sm <- summary(ma)
    pick <- function(M, cols) M[match(tnall, rownames(M)), cols, drop = FALSE]
    add("a_full", S(as.vector(t(pick(sm$coefmat.full, 1:3))))); add("a_cond", S(as.vector(t(pick(sm$coefmat.subset, 1:3))))); if (!byid) add("a_w", S(Weights(ma)))
    swv <- sw(ma); add("a_sw", S(swv[match(tn, names(swv))]))
    ci1 <- confint(ma, level = 0.9, full = TRUE); add("a_ci_full", S(as.vector(t(ci1[match(tnall, rownames(ci1)), ]))))
    if (is.null(varying)) {
      maf <- eval(bquote(model.avg(dr, subset = delta < .(cutoff), fit = TRUE)))
      p1 <- predict(maf, nd, se.fit = TRUE, type = "response"); add("p_resp_fit", S(p1$fit)); add("p_resp_se", S(p1$se.fit))
      add("p_coef_full", S(predict(maf, nd, full = TRUE)))
    }
  }
  if (gcases) {
    add("c_cp", Cp(gm)); add("c_df", attr(logLik(gm), "df")); add("c_dev", deviance(gm))
    if (!(fam %in% c(201, 202))) { add("c_ll", as.numeric(logLik(gm))); add("c_bic", BIC(gm)); add("c_aicc", AICc(gm)) }
    sc <- std.coef(gm, partial.sd = FALSE); add("c_stdsd", S(c(sc[, 1], sc[, 2])))
    r2 <- tryCatch(r.squaredGLMM(gm), error = function(e) NULL)
    if (!is.null(r2)) { add("c_r2m", S(r2[, 1])); add("c_r2c", S(r2[, 2])); add("c_r2n", nrow(r2)) }
  }
  invisible(dr)
}
flush <- function(name) { emit(name, c("MuMIn", "MASS", "lme4"), list(cases)); cases <<- list() }
set.seed(2026111802)
t5 <- c("a", "b", "c", "d", "e")
# prior weights and offsets
scenario(200, hasw = TRUE, deep = TRUE, gcases = TRUE)
scenario(200, haso = TRUE, rank = 1, gcases = TRUE)
scenario(200, hasw = TRUE, haso = TRUE, rank = 2, deep = TRUE)
scenario(2, hasw = TRUE, haso = TRUE, deep = TRUE, gcases = TRUE)
scenario(2, haso = TRUE, rank = 1)
scenario(1, binw = TRUE, hasw = TRUE, n = 40, deep = TRUE, gcases = TRUE)
scenario(4, hasw = TRUE, deep = TRUE, gcases = TRUE)
scenario(0, hasw = TRUE, haso = TRUE, gcases = TRUE)
scenario(8, hasw = TRUE, gcases = TRUE)
scenario(6, binw = TRUE, hasw = TRUE, n = 40, rank = 2)
flush("mumin_ext")
# aliased designs: e = a + b
scenario(200, tn = t5, deep = TRUE, gcases = TRUE, byid = TRUE)
scenario(2, tn = t5, deep = TRUE, gcases = TRUE, byid = TRUE)
scenario(1, tn = t5, n = 50, gcases = TRUE, byid = TRUE)
scenario(200, tn = t5, hasw = TRUE, rank = 2, byid = TRUE)
scenario(4, tn = t5, n = 40, byid = TRUE)
# negative binomial: fixed theta and glm.nb
scenario(9, theta = 2, deep = TRUE, gcases = TRUE, n = 40)
scenario(9, theta = 2, hasw = TRUE, haso = TRUE, rank = 1)
scenario(10, deep = TRUE, gcases = TRUE, n = 40)
scenario(10, hasw = TRUE, rank = 2, n = 40)
# quasi families in the criteria
scenario(201, rank = 5, deep = TRUE, gcases = TRUE)
scenario(202, rank = 5, n = 50, gcases = TRUE, hasw = TRUE)
scenario(2, rank = 4, chat = 1.8, deep = TRUE)
scenario(201, rank = 5, hasw = TRUE, haso = TRUE)
flush("mumin_ext2")
# varying: family x weights
scenario(5, n = 30, varying = list(family = alist(gaussian("log"), Gamma("log"))), vopts = rbind(c(0, 0, 5, 0, 0), c(0, 0, 4, 0, 0)))
scenario(5, n = 30, varying = list(family = alist(gaussian("log"), Gamma("log")), weights = alist(NULL, w)), vopts = rbind(c(0, 0, 5, 0, 0), c(0, 0, 4, 0, 0), c(1, 2, 0, 0, 0), c(1, 2, 0, 0, 1)), deep = TRUE)
scenario(200, n = 30, varying = list(weights = alist(NULL, w)), vopts = rbind(c(0, 2, 0, 0, 0), c(0, 2, 0, 0, 1)), rank = 1)
scenario(2, n = 30, varying = list(offset = alist(NULL, off)), vopts = rbind(c(0, 3, 0, 0, 0), c(0, 3, 0, 0, 1)))
# subset expressions, m.lim and fixed
scenario(200, expr = "a | b", tn = c("a", "b", "c", "d"), deep = TRUE)
scenario(200, expr = "!(a && b)")
scenario(200, expr = "!d | c")
scenario(200, expr = "sum(a, b, c) <= 2")
scenario(200, expr = "xor(a, b) && (c || d)")
scenario(200, expr = "dc(a, b, c)", rank = 1)
scenario(2, expr = "a & !(b | c)", rank = 2)
scenario(200, expr = "!(b && c)", fixed = "a", mlim = c(2, 3))
scenario(1, expr = "c | d", fixed = c("a", "b"), mlim = c(3, 3), n = 50)
scenario(200, expr = "(a && b) || (c && d) || sum(a, b, c, d) == 0", tn = c("a", "b", "c", "d"), mlim = c(0, 3), deep = TRUE)
flush("mumin_ext3")
# r.squaredGLMM of mixed models from the fitted pieces: args (cls, link, n, q, omega, nbin, var_resid, fixef0, fe[n], z[n q], sig[q q], sig0[q q])
mixed <- function(fam, slope, n_g = 10, per = 8) {
  g <- rep(seq_len(n_g), each = per); n <- length(g); x1 <- rnorm(n); x2 <- rnorm(n); b0 <- rnorm(n_g, 0, 0.6)[g]; b1 <- rnorm(n_g, 0, 0.3)[g]
  eta <- 0.2 + 0.5 * x1 - 0.3 * x2 + b0 + if (slope) b1 * x1 else 0
  y <- switch(fam, gaussian = eta + rnorm(n, 0, 0.5), poisson = rpois(n, exp(eta)), binomial = rbinom(n, 1, plogis(eta)))
  d <- data.frame(y = y, x1 = x1, x2 = x2, g = factor(g))
  re <- if (slope) "(x1 | g)" else "(1 | g)"; f <- as.formula(paste("y ~ x1 + x2 +", re)); f0 <- as.formula(paste("y ~ 1 +", re))
  m <- suppressWarnings(suppressMessages(if (fam == "gaussian") lmer(f, d) else glmer(f, d, family = fam)))
  m0 <- suppressWarnings(suppressMessages(if (fam == "gaussian") lmer(f0, d) else glmer(f0, d, family = fam)))
  r2 <- suppressWarnings(r.squaredGLMM(m, m0)); vc <- VarCorr(m)[["g"]]; vc0 <- VarCorr(m0)[["g"]]
  sig <- matrix(vc, nrow(vc)); sig0 <- matrix(vc0, nrow(vc0)); z <- if (slope) cbind(1, x1) else matrix(1, n, 1); q <- ncol(z)
  fe <- as.vector(model.matrix(m) %*% fixef(m)); cls <- switch(fam, gaussian = 0, binomial = 1, poisson = 2)
  a <- c(cls, if (fam == "binomial") 1 else if (fam == "poisson") 2 else 0, n, q, 1, 1, sigma(m)^2, fixef(m0)[[1]], fe, as.vector(z), as.vector(sig), as.vector(sig0))
  addc("gm_m", a, S(r2[, 1]), rel = 1e-7); addc("gm_c", a, S(r2[, 2]), rel = 1e-7); addc("gm_n", a, nrow(r2))
}
for (rep in 1:3) for (fam in c("gaussian", "poisson", "binomial")) for (slope in c(FALSE, TRUE)) mixed(fam, slope)
flush("mumin_ext4")
