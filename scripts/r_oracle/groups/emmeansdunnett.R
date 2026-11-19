# contrast(emmeans(lm(y ~ g), "g"), "trt.vs.ctrl", adjust = "mvt")$p.value for unbalanced one-way data (control = group 0): "dunnett" args (k, df, n0, t, n_1 .. n_{k-1}, c) the p of contrast c under adjust = "mvt" (emmeans integrates with randomised quasi-Monte Carlo, so the comparison is to 2e-3), and the dunnettx approximation in "dunnettx" cases (args as dunnett, exact)
suppressMessages(library(emmeans))
cases <- list()
set.seed(20271223)
for (rep in 1:14) {
  k <- sample(3:5, 1); ns <- sample(5:14, k, TRUE); g <- rep(0:(k - 1), ns); n <- length(g); y <- round(rnorm(n, mean = c(0, 0.4, 0.9, 0.3, 0.7)[g + 1], sd = 1), 3)
  d <- data.frame(g = factor(g), y = y); e <- emmeans(lm(y ~ g, d), "g"); s <- summary(contrast(e, "trt.vs.ctrl", adjust = "mvt"))
  sx <- summary(contrast(e, "trt.vs.ctrl", adjust = "dunnettx"))
  for (cc in seq_len(nrow(s))) cases[[length(cases) + 1]] <- case("dunnettx", c(k, s$df[cc], ns[1], s$t.ratio[cc], ns[-1], cc - 1), as.numeric(sx$p.value[cc]), rel = 1e-9, abs = 1e-10)
  for (cc in seq_len(nrow(s))) cases[[length(cases) + 1]] <- case("dunnett", c(k, s$df[cc], ns[1], s$t.ratio[cc], ns[-1], cc - 1), as.numeric(s$p.value[cc]), rel = 2e-3, abs = 2e-3)
}
emit("emmeansdunnett", "emmeans", list(cases))
