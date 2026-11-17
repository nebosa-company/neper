# MuMIn dredge, model.sel, model.avg, std.coef, r.squaredGLMM, Cp, QIC, stdize on lm and glm fits.
#   args of the model cases: (n, nt, fam, rank, chat, beta, mlo, mhi, fixed, cutoff, level, revised, resp, sefit, bt, n2, nrules, nextra, nsel,
#     then rules (kind, m1, m2) x nrules, parents x nt, extra kinds x nextra, selected masks x nsel, y x n, term columns x (n * nt), new rows (n2 * nt))
#   a term is a bit of a mask (term t is bit t); fam: 200 lm, 0 gaussian, 1 binomial logit, 2 poisson, 3 Gamma inverse, 4 Gamma log, 5 gaussian log,
#     6 binomial probit, 7 binomial cloglog, 8 inverse.gaussian log, 201 quasipoisson, 202 quasibinomial; rank: 0 AICc, 1 AIC, 2 BIC, 3 QAIC, 4 QAICc, 5 Cp
#   every case answers one quantity as sum(v * seq_along(v)) over R's order, NA as 0
suppressMessages(library(MuMIn)); suppressMessages(library(geepack))
options(na.action = "na.fail")
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-10)
S <- function(v) { v <- as.numeric(v); v[is.na(v)] <- 0; sum(v * seq_along(v)) }
famobj <- function(code) switch(as.character(code), "200" = NULL, "0" = gaussian(), "1" = binomial(), "2" = poisson(), "3" = Gamma(), "4" = Gamma("log"), "5" = gaussian("log"),
  "6" = binomial("probit"), "7" = binomial("cloglog"), "8" = inverse.gaussian("log"), "201" = quasipoisson(), "202" = quasibinomial())
rk <- c("AICc", "AIC", "BIC", "QAIC", "QAICc", "Cp")
rd <- function(x) round(x, 3)
gen <- function(fam, n) {
  a <- rd(runif(n, -1, 1)); b <- rd(runif(n, -1, 1)); c <- rd(runif(n, -1, 1)); d <- rd(runif(n, -1, 1))
  eta <- 0.3 + 0.6 * a - 0.5 * b + 0.3 * c
  y <- switch(as.character(fam), "200" = , "0" = eta + rnorm(n, 0, 0.5), "1" = , "202" = rbinom(n, 1, plogis(eta)), "6" = rbinom(n, 1, pnorm(eta)), "7" = rbinom(n, 1, 1 - exp(-exp(eta - 0.4))),
    "2" = , "201" = rpois(n, exp(eta)), "3" = rgamma(n, 4, 4 * (2 + 0.6 * a - 0.5 * b + 0.3 * c)), "4" = rgamma(n, 4, 4 / exp(eta)), "5" = exp(eta + rnorm(n, 0, 0.2)), "8" = exp(eta) * rgamma(n, 30, 30))
  y <- if (fam %in% c(1, 6, 7, 202, 2, 201)) y else rd(y)
  y <- if (fam %in% c(3, 4, 5, 8)) pmax(y, 0.01) else y
  data.frame(y = y, a = a, b = b, c = c, d = d)
}
fitm <- function(f, d, fam) if (fam == 200) eval(bquote(lm(.(f), data = d))) else eval(bquote(glm(.(f), family = .(famobj(fam)), data = d)))
# one scenario: terms tn (term names, mask bit order), interaction a:b present when "a:b" is among them
scenario <- function(fam, rank = 0, chat = 1, beta = 0, tn = c("a", "b", "c", "d"), fixed = character(), mlim = NULL, rules = list(), rexpr = NULL, extra = NULL, extrak = integer(), n = 30, gcases = FALSE, deep = FALSE) {
  d <- gen(fam, n)
  d$`a:b` <- NULL
  nt <- length(tn); bit <- function(nm) 2^(match(nm, tn) - 1)
  frm <- as.formula(paste("y ~", paste(tn, collapse = " + ")))
  gm <- fitm(frm, d, fam)
  dt <- d
  XX <- sapply(tn, function(z) if (z == "a:b") d$a * d$b else d[[z]])
  nd <- data.frame(a = rd(runif(5, -1, 1)), b = rd(runif(5, -1, 1)), c = rd(runif(5, -1, 1)), d = rd(runif(5, -1, 1)))
  XN <- sapply(tn, function(z) if (z == "a:b") nd$a * nd$b else nd[[z]])
  parents <- sapply(tn, function(z) if (z == "a:b") bit("a") + bit("b") else 0)
  fixedmask <- sum(unlist(lapply(fixed, bit)))
  ml <- if (is.null(mlim)) c(0, nt) else mlim
  args <- list(rank = rk[rank + 1], chat = chat)
  dr <- do.call(dredge, c(list(gm, beta = c("none", "sd", "partial.sd")[beta + 1], fixed = if (length(fixed)) fixed else NULL, m.lim = mlim, extra = extra, trace = FALSE), if (rank == 0) list() else if (rank == 3 || rank == 4) list(rank = rk[rank + 1], chat = chat) else list(rank = rk[rank + 1]),
    if (!is.null(rexpr)) list(subset = rexpr) else list()))
  nm <- nrow(dr); cutoff <- dr$delta[min(5, nm)] + 1e-6
  tnall <- c("(Intercept)", tn)
  cfg <- function(resp = 0, sefit = 0, bt = 0, revised = 1, level = 0.95, selm = numeric()) c(n, nt, fam, rank, chat, beta, ml[1], ml[2], fixedmask, cutoff, level, revised, resp, sefit, bt, 5, length(rules), length(extrak), length(selm),
    unlist(lapply(rules, unlist)), parents, extrak, selm, d$y, as.vector(XX), as.vector(XN))
  a0 <- cfg()
  est <- as.matrix(dr[, tnall]); est[] <- as.numeric(est)
  cts <- attr(dr, "coefTables")
  sem <- cdf <- est; sem[] <- NA; cdf[] <- NA
  for (i in seq_len(nm)) { ct <- cts[[i]]; rn <- MuMIn:::fixCoefNames(rownames(ct)); sem[i, rn] <- ct[, 2]; cdf[i, rn] <- ct[, 3] }
  add("t_id", a0, S(as.numeric(rownames(dr))))
  add("t_df", a0, S(dr$df)); add("t_ll", a0, S(dr$logLik)); add("t_ic", a0, S(dr[[rk[rank + 1]]])); add("t_delta", a0, S(dr$delta)); add("t_weight", a0, S(dr$weight))
  add("t_est", a0, S(est)); add("t_se", a0, S(sem))
  for (k in seq_along(extrak)) add(paste0("t_ex", k), a0, S(dr[[colnames(dr)[length(tn) + 1 + k]]]))
  if (deep) {
  # model.avg on a subset; summary at level 0.95
  rows <- which(dr$delta < cutoff)
  ma <- eval(bquote(model.avg(dr, subset = delta < .(cutoff))))
  sm <- summary(ma); pick <- function(M, cols) { M <- M[match(tnall, rownames(M)), cols, drop = FALSE]; M }
  add("a_full", a0, S(as.vector(t(pick(sm$coefmat.full, 1:3))))); add("a_cond", a0, S(as.vector(t(pick(sm$coefmat.subset, 1:3)))))
  add("a_w", a0, S(Weights(ma))); swv <- sw(ma); add("a_sw", a0, S(swv[match(tn, names(swv))])); add("a_n", a0, S(attr(swv, "n.models")[match(tn, names(swv))]))
  add("a_coef", a0, S(c(coef(ma, full = TRUE)[tnall], coef(ma, full = FALSE)[tnall])))
  ma2 <- eval(bquote(model.avg(dr, subset = delta < .(cutoff), revised.var = FALSE))); sm2 <- summary(ma2)
  add("a_full_nr", cfg(revised = 0), S(as.vector(t(pick(sm2$coefmat.full, 1:3))))); add("a_cond_nr", cfg(revised = 0), S(as.vector(t(pick(sm2$coefmat.subset, 1:3)))))
  ci1 <- confint(ma, level = 0.9, full = TRUE); ci2 <- confint(ma, level = 0.9, full = FALSE)
  add("a_ci_full", cfg(level = 0.9), S(as.vector(t(ci1[match(tnall, rownames(ci1)), ])))); add("a_ci_cond", cfg(level = 0.9), S(as.vector(t(ci2[match(tnall, rownames(ci2)), ]))))
  if (beta == 0) {
    maf <- eval(bquote(model.avg(dr, subset = delta < .(cutoff), fit = TRUE)))
    v1 <- vcov(maf, full = TRUE); v2 <- vcov(maf, full = FALSE); mm <- match(tnall, rownames(v1))
    add("a_vcov_full", a0, S(v1[mm, mm])); add("a_vcov_cond", a0, S(v2[mm, mm]))
    add("p_coef_full", a0, S(predict(maf, nd, full = TRUE))); add("p_coef_cond", a0, S(predict(maf, nd, full = FALSE)))
    p1 <- predict(maf, nd, se.fit = TRUE, type = "response")
    add("p_resp_fit", cfg(resp = 1, sefit = 1), S(p1$fit)); add("p_resp_se", cfg(resp = 1, sefit = 1), S(p1$se.fit))
    if (fam != 200) {
      p2 <- predict(maf, nd, se.fit = TRUE, type = "link")
      add("p_link_fit", cfg(resp = 0, sefit = 1), S(p2$fit)); add("p_link_se", cfg(resp = 0, sefit = 1), S(p2$se.fit))
      p3 <- predict(maf, nd, backtransform = TRUE, se.fit = TRUE)
      add("p_bt_fit", cfg(sefit = 1, bt = 1), S(p3$fit)); add("p_bt_se", cfg(sefit = 1, bt = 1), S(p3$se.fit))
    }
    p4 <- predict(maf, nd, type = "response")
    add("p_resp_mean", cfg(resp = 1, sefit = 0), S(p4))
    # model.sel on five models taken from the table (their masks), listed in a shuffled order
    ids <- sample(nrow(dr), min(5, nm)); selm <- sapply(ids, function(i) sum(2^(which(!is.na(est[i, tn])) - 1)))
    mods <- lapply(ids, function(i) fitm(as.formula(paste("y ~", paste(c("1", tn[!is.na(est[i, tn])]), collapse = " + "))), d, fam))
    ms <- if (rank %in% c(3, 4)) model.sel(mods, rank = if (rank == 3) QAIC else QAICc, rank.args = list(chat = chat)) else model.sel(mods, rank = switch(rank + 1, AICc, AIC, BIC, NULL, NULL, Cp))
    a1 <- cfg(selm = selm); ord <- as.numeric(rownames(ms))
    add("s_order", a1, S(ord)); add("s_ic", a1, S(ms[[ncol(ms) - 2]])); add("s_delta", a1, S(ms$delta)); add("s_weight", a1, S(ms$weight)); add("s_df", a1, S(ms$df))
  }
  }
  if (gcases) {
    gmq <- gm
    add("c_cp", a0, Cp(gmq)); add("c_cp_disp", a0, Cp(gmq, dispersion = 1.7))
    if (!(fam %in% c(201, 202))) { add("c_bic", a0, BIC(gmq)); add("c_aicc", a0, AICc(gmq)); add("c_qaic", cfg(), QAIC(gmq, chat = 1.4)); add("c_qaicc", cfg(), QAICc(gmq, chat = 1.4)) }
    sc <- std.coef(gmq, partial.sd = FALSE); sp <- std.coef(gmq, partial.sd = TRUE)
    add("c_stdsd", a0, S(c(sc[, 1], sc[, 2]))); add("c_stdpsd", a0, S(c(sp[, 1], sp[, 2])))
    r2 <- tryCatch(r.squaredGLMM(gmq), error = function(e) NULL)
    if (!is.null(r2)) { add("c_r2m", a0, S(r2[, 1])); add("c_r2c", a0, S(r2[, 2])); add("c_r2n", a0, nrow(r2)) }
  }
  invisible(dr)
}
set.seed(2026111801)
flush <- function(name) { emit(name, c("MuMIn", "geepack"), list(cases)); cases <<- list() }
# interaction scenarios need the a:b term after the main effects
t5 <- c("a", "b", "c", "d", "a:b")
scenario(deep = TRUE, 200, tn = t5, extra = c("AIC", "BIC", "R^2", "adjR^2"), extrak = c(1, 2, 6, 7))
scenario(200, rank = 0, tn = t5, gcases = TRUE)
scenario(200, rank = 1, fixed = "a", mlim = c(1, 3))
scenario(deep = TRUE, 200, rank = 2, rexpr = expression(!(c && d)), rules = list(c(0, 12, 0)))
scenario(200, rank = 5, tn = c("a", "b", "c", "d"), rexpr = expression(dc(a, b, c)), rules = list(c(6, 7, 0)))
scenario(200, beta = 1, tn = t5)
scenario(200, beta = 2, tn = t5)
scenario(200, rank = 4, chat = 1.3)
scenario(deep = TRUE, 200, rank = 3, chat = 1.6, rexpr = expression(!d || c), rules = list(c(2, 8, 4)))
flush("mumin_dredge")
scenario(1, tn = t5, n = 60, gcases = TRUE, deep = TRUE)
scenario(6, n = 60, rank = 1, gcases = TRUE)
scenario(7, n = 80, rank = 2, gcases = TRUE)
scenario(2, tn = t5, gcases = TRUE, deep = TRUE)
scenario(2, rank = 1, fixed = c("a", "b"))
scenario(2, rank = 3, chat = 1.7, deep = TRUE)
flush("mumin_dredge4")
scenario(4, n = 50, gcases = TRUE, deep = TRUE)
scenario(3, n = 50, rank = 4, chat = 1.2, gcases = TRUE, deep = TRUE)
scenario(0, tn = t5, gcases = TRUE, deep = TRUE)
scenario(5, n = 50, gcases = TRUE)
scenario(8, n = 50, gcases = TRUE, deep = TRUE)
scenario(201, rank = 5, gcases = TRUE)
scenario(202, rank = 5, n = 60, gcases = TRUE)
scenario(2, beta = 2)
scenario(1, beta = 1, n = 60)
flush("mumin_dredge5")
# r.squaredGLMM and the criteria need the global model only: the c_ cases above carry them; stdize follows
for (rep in 1:8) {
  n <- sample(8:30, 1); x <- rd(rnorm(n, 2, 3)); z <- rbinom(n, 1, 0.4); z[1:2] <- c(0, 1)
  z <- factor(z); sdm <- c(1, 2, 0.5)[(rep %% 3) + 1]
  for (bm in 0:3) {
    df <- data.frame(x = x, z = z)
    zz <- stdize(df, binary = c("center", "scale", "binary", "half")[bm + 1], scale = function(v) sdm * sd(v))
    a <- c(n, bm, sdm, x, as.numeric(z) - 1)
    add("z_x", a, S(zz[[1]])); add("z_z", a, S(zz[[2]]))
    add("z_cx", a, S(attr(zz, "scaled:center")[1])); add("z_sx", a, S(attr(zz, "scaled:scale")[1]))
    add("z_cz", a, S(attr(zz, "scaled:center")[2])); add("z_sz", a, S(attr(zz, "scaled:scale")[2]))
  }
}
flush("mumin_dredge2")
# QIC / QICu of geeglm fits: args (p, n, cls, scale, typeR, y, mu, vbeta, vnaive)
for (rep in 1:12) {
  k <- 12; mm <- 4; id <- rep(1:k, each = mm); x1 <- rnorm(k * mm); x2 <- rnorm(k * mm)
  fam <- c("gaussian", "binomial", "poisson", "Gamma")[(rep %% 4) + 1]; cls <- (rep %% 4)
  eta <- 0.2 + 0.4 * x1 - 0.3 * x2 + rep(rnorm(k, 0, 0.3), each = mm)
  y <- switch(fam, gaussian = eta + rnorm(k * mm), binomial = rbinom(k * mm, 1, plogis(eta)), poisson = rpois(k * mm, exp(eta)), Gamma = rgamma(k * mm, 5, 5 / exp(eta)))
  df <- data.frame(y = y, x1 = x1, x2 = x2, id = id)
  fm <- geeglm(y ~ x1 + x2, family = fam, id = id, data = df, corstr = c("exchangeable", "ar1")[(rep %% 2) + 1])
  if (fam == "Gamma") fm <- geeglm(y ~ x1 + x2, family = Gamma("log"), id = id, data = df, corstr = "exchangeable")
  fi <- geeglm(formula(fm), family = family(fm), id = id, data = df, corstr = "independence")
  cl <- if (fam == "Gamma") 3 else cls
  for (tr in c(FALSE, TRUE)) {
    q <- MuMIn:::getQIC(fm, typeR = tr)
    a <- c(3, nrow(df), cl, fm$geese$gamma[[1]], tr, df$y, if (tr) fm$fitted.values else fi$fitted.values, as.vector(fm$geese$vbeta), as.vector(fi$geese$vbeta.naiv))
    add("qic", a, q[1]); add("qicu", a, q[2])
  }
}
flush("mumin_dredge3")
