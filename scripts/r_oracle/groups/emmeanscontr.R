# the coefficient matrices of emmeans' *.emmc functions for k levels: "emmc" args (kind 0 pairwise, 1 revpairwise, 2 trt.vs.ctrl, 3 trt.vs.ctrlk, 4 consec, 5 eff, 6 del.eff, 7 poly, k, r, c) level r of contrast c
suppressMessages(library(emmeans))
cases <- list()
fns <- c("pairwise", "revpairwise", "trt.vs.ctrl", "trt.vs.ctrlk", "consec", "eff", "del.eff", "poly")
for (kind in 0:7) for (k in 3:7) {
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
emit("emmeanscontr", "emmeans", list(cases))
