# the coefficient matrices of emmeans' *.emmc functions for k levels: "emmc" args (kind 0 pairwise, 1 revpairwise, 2 trt.vs.ctrl, 3 trt.vs.ctrlk, 4 consec, 5 eff, 6 del.eff, 7 poly, k, r, c) level r of contrast c
suppressMessages(library(emmeans))
cases <- list()
fns <- c("pairwise", "revpairwise", "trt.vs.ctrl", "trt.vs.ctrlk", "consec", "eff", "del.eff", "poly", "mean_chg", "identity")
for (kind in 0:9) for (k in 3:7) {
  M <- as.matrix(get(paste0(fns[kind + 1], ".emmc"))(1:k))
  for (r in seq_len(nrow(M))) for (cc in seq_len(ncol(M))) cases[[length(cases) + 1]] <- case("emmc", c(kind, k, r - 1, cc - 1), M[r, cc], rel = 1e-9, abs = 1e-9)
}
# contrast(emmeans(lm(y ~ g), "g"), method, adjust = "none") for unbalanced one-way data: "emmo" args (kind, k, n, g[n] 0-based, y[n], c, f) contrast c, f 0 estimate, 1 SE, 2 df, 3 t ratio, 4 p, 5 Tukey p (pairwise kinds only), 6 Scheffe p, 7 Bonferroni p, 8 Sidak p, 9 Holm p
meth <- c("pairwise", "revpairwise", "trt.vs.ctrl", "trt.vs.ctrlk", "consec", "eff", "del.eff", "poly")
set.seed(20271222)
for (rep in 1:12) {
  k <- sample(3:5, 1); ns <- sample(4:12, k, TRUE); g <- rep(0:(k - 1), ns); n <- length(g); y <- round(rnorm(n, mean = c(0, 0.5, 1, 0.3, 0.8)[g + 1], sd = 1), 3)
  d <- data.frame(g = factor(g), y = y); e <- emmeans(lm(y ~ g, d), "g")
  for (kind in 0:7) {
    s <- summary(contrast(e, meth[kind + 1], adjust = "none")); st <- if (kind <= 1) summary(contrast(e, meth[kind + 1], adjust = "tukey"))$p.value else rep(NaN, nrow(s))
    sa <- lapply(c("scheffe", "bonferroni", "sidak", "holm"), function(ad) summary(contrast(e, meth[kind + 1], adjust = ad))$p.value)
    for (cc in seq_len(nrow(s))) { v <- c(s$estimate[cc], s$SE[cc], s$df[cc], s$t.ratio[cc], s$p.value[cc], st[cc], sa[[1]][cc], sa[[2]][cc], sa[[3]][cc], sa[[4]][cc]); for (ff in 0:9) if (is.finite(v[ff + 1])) cases[[length(cases) + 1]] <- case("emmoneway", c(kind, k, n, g, y, cc - 1, ff), as.numeric(v[ff + 1]), rel = 1e-8, abs = 1e-10) }
  }
}
# the same with a covariate, lm(y ~ g + x): "emmancova" args (kind, k, n, g[n], y[n], x[n], c, f), the means taken at the mean of x
for (rep in 1:8) {
  k <- sample(3:5, 1); ns <- sample(5:12, k, TRUE); g <- rep(0:(k - 1), ns); n <- length(g); x <- round(rnorm(n, 1, 1), 3); y <- round(c(0, 0.5, 1, 0.3, 0.8)[g + 1] + 0.7 * x + rnorm(n), 3)
  d <- data.frame(g = factor(g), y = y, x = x); e <- emmeans(lm(y ~ g + x, d), "g")
  for (kind in 0:7) {
    s <- summary(contrast(e, meth[kind + 1], adjust = "none")); st <- if (kind <= 1) summary(contrast(e, meth[kind + 1], adjust = "tukey"))$p.value else rep(NaN, nrow(s))
    sa <- lapply(c("scheffe", "bonferroni", "sidak", "holm"), function(ad) summary(contrast(e, meth[kind + 1], adjust = ad))$p.value)
    for (cc in seq_len(nrow(s))) { v <- c(s$estimate[cc], s$SE[cc], s$df[cc], s$t.ratio[cc], s$p.value[cc], st[cc], sa[[1]][cc], sa[[2]][cc], sa[[3]][cc], sa[[4]][cc]); for (ff in 0:9) if (is.finite(v[ff + 1])) cases[[length(cases) + 1]] <- case("emmancovar", c(kind, k, n, g, y, x, cc - 1, ff), as.numeric(v[ff + 1]), rel = 1e-8, abs = 1e-10) }
  }
}
# additive two-factor model lm(y ~ g + h), the means of g averaged over the levels of h: "emmtwoway" args (kind, k, n, nh, g[n], y[n], hdummies[n * (nh - 1)] column-major, c, f)
for (rep in 1:8) {
  k <- sample(3:4, 1); nh <- sample(2:3, 1); n <- sample(40:70, 1); g <- sample(0:(k - 1), n, TRUE); h <- sample(0:(nh - 1), n, TRUE)
  if (length(unique(g)) < k || length(unique(h)) < nh) next
  y <- round(c(0, 0.5, 1, 0.3)[g + 1] + c(0, 0.6, -0.4)[h + 1] + rnorm(n), 3)
  d <- data.frame(g = factor(g), h = factor(h), y = y); e <- emmeans(lm(y ~ g + h, d), "g"); hd <- as.vector(sapply(1:(nh - 1), function(l) as.numeric(h == l)))
  for (kind in 0:7) {
    s <- summary(contrast(e, meth[kind + 1], adjust = "none")); st <- if (kind <= 1) summary(contrast(e, meth[kind + 1], adjust = "tukey"))$p.value else rep(NaN, nrow(s))
    sa <- lapply(c("scheffe", "bonferroni", "sidak", "holm"), function(ad) summary(contrast(e, meth[kind + 1], adjust = ad))$p.value)
    for (cc in seq_len(nrow(s))) { v <- c(s$estimate[cc], s$SE[cc], s$df[cc], s$t.ratio[cc], s$p.value[cc], st[cc], sa[[1]][cc], sa[[2]][cc], sa[[3]][cc], sa[[4]][cc]); for (ff in 0:9) if (is.finite(v[ff + 1])) cases[[length(cases) + 1]] <- case("emmtwowayadd", c(kind, k, n, nh, g, y, hd, cc - 1, ff), as.numeric(v[ff + 1]), rel = 1e-8, abs = 1e-10) }
  }
}
# interaction model lm(y ~ g * h): "emminteract" args (kind, k, n, nh, g[n], h[n], y[n], c, f)
for (rep in 1:8) {
  k <- sample(3:4, 1); nh <- sample(2:3, 1); n <- sample(50:80, 1); g <- sample(0:(k - 1), n, TRUE); h <- sample(0:(nh - 1), n, TRUE)
  if (any(table(g, h) < 2)) next
  y <- round(c(0, 0.5, 1, 0.3)[g + 1] + c(0, 0.6, -0.4)[h + 1] + 0.4 * (g == 1) * (h == 1) + rnorm(n), 3)
  d <- data.frame(g = factor(g), h = factor(h), y = y); e <- emmeans(lm(y ~ g * h, d), "g")
  for (kind in 0:7) {
    s <- summary(contrast(e, meth[kind + 1], adjust = "none")); st <- if (kind <= 1) summary(contrast(e, meth[kind + 1], adjust = "tukey"))$p.value else rep(NaN, nrow(s))
    sa <- lapply(c("scheffe", "bonferroni", "sidak", "holm"), function(ad) summary(contrast(e, meth[kind + 1], adjust = ad))$p.value)
    for (cc in seq_len(nrow(s))) { v <- c(s$estimate[cc], s$SE[cc], s$df[cc], s$t.ratio[cc], s$p.value[cc], st[cc], sa[[1]][cc], sa[[2]][cc], sa[[3]][cc], sa[[4]][cc]); for (ff in 0:9) if (is.finite(v[ff + 1]) && !(ff == 6 && kind %in% 5:6)) cases[[length(cases) + 1]] <- case("emminteract", c(kind, k, n, nh, g, h, y, cc - 1, ff), as.numeric(v[ff + 1]), rel = 1e-8, abs = 1e-10) }
  }
}
# logistic regression glm(y ~ g, binomial): "emmlogit" args (kind, k, n, g[n], y[n], c, f) f 0 link estimate, 1 SE, 2 z, 3 p, 4 response-scale estimate, 5 SE, 6 z, 7 p (contrast of regrid(emmeans))
for (rep in 1:10) {
  k <- sample(3:5, 1); ns <- sample(20:50, k, TRUE); g <- rep(0:(k - 1), ns); n <- length(g); y <- rbinom(n, 1, plogis(c(-0.5, 0.3, 0.9, -0.2, 0.6)[g + 1]))
  if (any(tapply(y, g, function(v) length(unique(v))) < 2)) next
  d <- data.frame(g = factor(g), y = y); e <- emmeans(glm(y ~ g, binomial, d), "g"); er <- regrid(e)
  for (kind in 0:7) {
    s1 <- summary(contrast(e, meth[kind + 1], adjust = "none")); s2 <- summary(contrast(er, meth[kind + 1], adjust = "none"))
    for (cc in seq_len(nrow(s1))) { v <- c(s1$estimate[cc], s1$SE[cc], s1$z.ratio[cc], s1$p.value[cc], s2$estimate[cc], s2$SE[cc], s2$z.ratio[cc], s2$p.value[cc]); for (ff in 0:7) cases[[length(cases) + 1]] <- case("emmlogit", c(kind, k, n, g, y, cc - 1, ff), as.numeric(v[ff + 1]), rel = 5e-4, abs = 1e-5) }
  }
}
# Poisson regression glm(y ~ g, poisson): "emmpois" args as emmlogit, the means being exp(beta)
for (rep in 1:8) {
  k <- sample(3:5, 1); ns <- sample(15:40, k, TRUE); g <- rep(0:(k - 1), ns); n <- length(g); y <- rpois(n, exp(c(0.5, 1, 1.4, 0.8, 1.2)[g + 1]))
  d <- data.frame(g = factor(g), y = y); e <- emmeans(glm(y ~ g, poisson, d), "g"); er <- regrid(e)
  for (kind in 0:7) {
    s1 <- summary(contrast(e, meth[kind + 1], adjust = "none")); s2 <- summary(contrast(er, meth[kind + 1], adjust = "none"))
    for (cc in seq_len(nrow(s1))) { v <- c(s1$estimate[cc], s1$SE[cc], s1$z.ratio[cc], s1$p.value[cc], s2$estimate[cc], s2$SE[cc], s2$z.ratio[cc], s2$p.value[cc]); for (ff in 0:7) cases[[length(cases) + 1]] <- case("emmpois", c(kind, k, n, g, y, cc - 1, ff), as.numeric(v[ff + 1]), rel = 5e-4, abs = 1e-5) }
  }
}
emit("emmeanscontr", "emmeans", list(cases))
