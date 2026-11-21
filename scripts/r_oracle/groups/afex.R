# afex aov_ez, Type III: one within factor (k levels) and an optional between factor (g groups of equal size).
#   args: (n subjects, g, k, then per subject: group index 0-based, k responses)
#   fn is the output slot: F_A p_A F_B p_B F_AB p_AB gg hf ggp_B hfp_B ggp_AB hfp_AB W pW ges_A ges_B ges_AB
suppressMessages(library(afex))
cases <- list()
slots <- c("F_A", "p_A", "F_B", "p_B", "F_AB", "p_AB", "gg", "hf", "ggp_B", "hfp_B", "ggp_AB", "hfp_AB", "W", "pW", "ges_A", "ges_B", "ges_AB")
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261207)
for (rep in 1:16) {
  g <- c(1, 2, 3, 2)[(rep - 1) %% 4 + 1]; per <- sample(6:10, 1); k <- sample(3:5, 1); n <- g * per
  grp <- rep(0:(g - 1), each = per)
  sub <- rnorm(n); y <- matrix(rnorm(n * k), n) + sub + outer(grp, seq_len(k), function(a, b) 0.3 * a * b / k) + rep(seq_len(k) / 2, each = n)
  d <- data.frame(id = factor(rep(seq_len(n), each = k)), A = factor(rep(grp, each = k)), B = factor(rep(seq_len(k), n)), y = as.vector(t(y)))
  a <- if (g > 1) suppressMessages(aov_ez("id", "y", d, between = "A", within = "B", type = 3)) else suppressMessages(aov_ez("id", "y", d, within = "B", type = 3))
  gg <- anova(a, correction = "GG", es = "ges"); hf <- anova(a, correction = "HF", es = "ges"); no <- anova(a, correction = "none", es = "ges")
  s <- summary(a$Anova); ad <- s$pval.adjustments; sp <- s$sphericity.tests
  args <- c(n, g, k, as.vector(t(cbind(grp, y))))
  rows <- rownames(no)
  v <- rep(NA_real_, 17)
  if (g > 1) { v[1] <- no["A", "F"]; v[2] <- no["A", "Pr(>F)"]; v[5] <- no["A:B", "F"]; v[6] <- no["A:B", "Pr(>F)"]; v[11] <- ad["A:B", "Pr(>F[GG])"]; v[12] <- ad["A:B", "Pr(>F[HF])"]; v[15] <- no["A", "ges"]; v[17] <- no["A:B", "ges"] }
  v[3] <- no["B", "F"]; v[4] <- no["B", "Pr(>F)"]; v[7] <- ad["B", "GG eps"]; v[8] <- ad["B", "HF eps"]; v[9] <- ad["B", "Pr(>F[GG])"]; v[10] <- ad["B", "Pr(>F[HF])"]
  v[16] <- no["B", "ges"]
  if (!is.null(sp)) { v[13] <- sp["B", "Test statistic"]; v[14] <- sp["B", "p-value"] }
  for (i in seq_along(v)) add(slots[i], args, v[i])
}
emit("afex", "afex", list(cases))
