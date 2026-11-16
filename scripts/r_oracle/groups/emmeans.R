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
  pt <- summary(pairs(e, adjust = "tukey")); ph <- summary(pairs(e, adjust = "holm")); pb <- summary(pairs(e, adjust = "bonferroni"))
  r <- 0
  for (i in 1:(a - 1)) for (j in (i + 1):a) {
    r <- r + 1; ar <- c(base, i - 1, j - 1)
    add("pair_est", ar, pt$estimate[r]); add("pair_se", ar, pt$SE[r]); add("pair_t", ar, pt$t.ratio[r])
    add("p_tukey", ar, pt$p.value[r]); add("p_holm", ar, ph$p.value[r]); add("p_bonf", ar, pb$p.value[r])
  }
}
emit("emmeans", "emmeans", list(cases))
