# emmeans for lm(y ~ A + B + x): EMMs of A with SEs, pairwise contrasts with Tukey, Holm and Bonferroni p values.
#   args: (n, a, b, y[n], A[n] 0-based, B[n] 0-based, x[n], i, j)   fn "emm" "se" (level i) "df" "pair_est" "pair_se" "pair_t" "p_tukey" "p_holm" "p_bonf" (pair i<j)
suppressMessages(library(emmeans))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-6, abs = 1e-9)
set.seed(20261116)
for (rep in 1:8) {
  a <- sample(3:4, 1); b <- sample(2:3, 1); n <- sample(40:70, 1)
  A <- c(0:(a - 1), sample(0:(a - 1), n - a, TRUE)); B <- c(sample(0:(b - 1), a, TRUE), sample(0:(b - 1), n - a, TRUE)); B[1:b] <- 0:(b - 1)
  x <- round(rnorm(n), 3); y <- round(2 + A * 0.7 + B * 0.4 + x + rnorm(n), 3)
  d <- data.frame(y = y, A = factor(A), B = factor(B), x = x)
  m <- lm(y ~ A + B + x, d); e <- emmeans(m, "A")
  s <- summary(e); base <- c(n, a, b, y, A, B, x)
  for (i in 1:a) { add("emm", c(base, i - 1, 0), s$emmean[i]); add("se", c(base, i - 1, 0), s$SE[i]) }
  add("df", c(base, 0, 0), s$df[1])
  pt <- summary(pairs(e, adjust = "tukey")); ph <- summary(pairs(e, adjust = "holm")); pb <- summary(pairs(e, adjust = "bonferroni")); ps <- summary(pairs(e, adjust = "scheffe"))
  r <- 0
  for (i in 1:(a - 1)) for (j in (i + 1):a) {
    r <- r + 1; ar <- c(base, i - 1, j - 1)
    add("pair_est", ar, pt$estimate[r]); add("pair_se", ar, pt$SE[r]); add("pair_t", ar, pt$t.ratio[r])
    add("p_scheffe", ar, ps$p.value[r]); add("p_tukey", ar, pt$p.value[r]); add("p_holm", ar, ph$p.value[r]); add("p_bonf", ar, pb$p.value[r])
  }
}
# joint_tests of lm(y ~ A + B + x) (emmeans rounds the F ratio to 3 decimals and the p value to 4, hence the tolerances): "jt_F" "jt_p" args (base..., term 0 A 1 B 2 x, 0)
for (rep in 1:8) {
  a <- sample(3:4, 1); b <- sample(2:3, 1); n <- sample(40:70, 1)
  A <- c(0:(a - 1), sample(0:(a - 1), n - a, TRUE)); B <- c(sample(0:(b - 1), a, TRUE), sample(0:(b - 1), n - a, TRUE)); B[1:b] <- 0:(b - 1)
  x <- round(rnorm(n), 3); y <- round(2 + A * 0.7 + B * 0.4 + x + rnorm(n), 3)
  d <- data.frame(y = y, A = factor(A), B = factor(B), x = x)
  m <- lm(y ~ A + B + x, d); jt <- as.data.frame(joint_tests(m)); base <- c(n, a, b, y, A, B, x)
  for (t in 0:2) { cases[[length(cases) + 1]] <- case("jt_F", c(base, t, 0), jt$F.ratio[t + 1], rel = 1e-4, abs = 6e-4); cases[[length(cases) + 1]] <- case("jt_p", c(base, t, 0), jt$p.value[t + 1], rel = 1e-3, abs = 6e-4) }
}
# contrast families (adjust = "none"): "ctr_est" and "ctr_se" with args (base..., type, idx): type 0 trt.vs.ctrl (level idx vs level 0, idx from 1), 1 revpairwise (pair idx in emmeans' order), 2 consec (idx from 1), 3 eff (level idx, from 0), 4 poly (degree idx from 1)
for (rep in 1:8) {
  a <- sample(3:4, 1); b <- sample(2:3, 1); n <- sample(40:70, 1)
  A <- c(0:(a - 1), sample(0:(a - 1), n - a, TRUE)); B <- c(sample(0:(b - 1), a, TRUE), sample(0:(b - 1), n - a, TRUE)); B[1:b] <- 0:(b - 1)
  x <- round(rnorm(n), 3); y <- round(2 + A * 0.7 + B * 0.4 + x + rnorm(n), 3)
  d <- data.frame(y = y, A = factor(A), B = factor(B), x = x)
  m <- lm(y ~ A + B + x, d); e <- emmeans(m, "A"); base <- c(n, a, b, y, A, B, x)
  mk <- function(meth, type) { sm <- summary(contrast(e, meth, adjust = "none")); for (r in seq_len(nrow(sm))) {
    cases[[length(cases) + 1]] <<- case("ctr_est", c(base, type, r), sm$estimate[r], rel = 1e-6, abs = 1e-9)
    cases[[length(cases) + 1]] <<- case("ctr_se", c(base, type, r), sm$SE[r], rel = 1e-6, abs = 1e-9) } }
  mk("trt.vs.ctrl", 0); mk("revpairwise", 1); mk("consec", 2)
  sm <- summary(contrast(e, "eff", adjust = "none")); for (r in 1:nrow(sm)) { cases[[length(cases) + 1]] <- case("ctr_est", c(base, 3, r - 1), sm$estimate[r], rel = 1e-6, abs = 1e-9); cases[[length(cases) + 1]] <- case("ctr_se", c(base, 3, r - 1), sm$SE[r], rel = 1e-6, abs = 1e-9) }
  sm <- summary(contrast(e, "poly", adjust = "none")); for (r in 1:nrow(sm)) { cases[[length(cases) + 1]] <- case("ctr_est", c(base, 4, r), sm$estimate[r], rel = 1e-6, abs = 1e-9); cases[[length(cases) + 1]] <- case("ctr_se", c(base, 4, r), sm$SE[r], rel = 1e-6, abs = 1e-9) }
}
# emtrends of lm(y ~ A * x): the slope of x within each level of A and its SE, and the pairwise slope differences: "trend_est", "trend_se" args (n, a, y, A 0-based, x, level), "trend_pair_est", "trend_pair_se" (level i, level j)
for (rep in 1:10) {
  a <- sample(3:4, 1); n <- sample(40:80, 1)
  A <- c(0:(a - 1), sample(0:(a - 1), n - a, TRUE)); x <- round(rnorm(n), 3); y <- round(1 + 0.5 * A + (0.4 + 0.3 * A) * x + rnorm(n), 3)
  d <- data.frame(y = y, A = factor(A), x = x); m <- lm(y ~ A * x, d)
  tr <- emtrends(m, "A", var = "x"); s <- summary(tr); base <- c(n, a, y, A, x)
  for (i in 1:a) { cases[[length(cases) + 1]] <- case("trend_est", c(base, i - 1, 0), s$x.trend[i], rel = 1e-8, abs = 1e-10); cases[[length(cases) + 1]] <- case("trend_se", c(base, i - 1, 0), s$SE[i], rel = 1e-8, abs = 1e-10) }
  pr <- summary(pairs(tr, adjust = "none")); r <- 0
  for (i in 1:(a - 1)) for (j in (i + 1):a) { r <- r + 1
    cases[[length(cases) + 1]] <- case("trend_pair_est", c(base, i - 1, j - 1), pr$estimate[r], rel = 1e-8, abs = 1e-10)
    cases[[length(cases) + 1]] <- case("trend_pair_se", c(base, i - 1, j - 1), pr$SE[r], rel = 1e-8, abs = 1e-10) }
}
emit("emmeans", "emmeans", list(cases))
