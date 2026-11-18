# vcd assocstats and Kappa; effectsize cohens_d, hedges_g, glass_delta, rank_biserial, eta/omega/epsilon squared (one-way).
#   as: (r, c, table row-major[r*c], q) fn "as"  q 0 LR 1 Pearson 2 df 3 pLR 4 pPearson 5 phi (2x2) 6 contingency 7 cramer
#   kp: (k, wtype 0 equal 1 fleiss, table row-major[k*k], q) fn "kp" q 0 unweighted 1 ASE 2 weighted 3 ASE
#   smd: (n1, n2, x, y, q) fn "smd" q 0 d 1 g 2 glass 3 rank-biserial;  aov: (G, sizes[G], y[N], q) fn "aov" q 0 eta2 1 omega2 2 epsilon2
suppressMessages({ library(vcd); library(effectsize) })
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-10)
set.seed(20261116)
for (rep in 1:30) {
  r <- sample(2:4, 1); cc <- sample(2:4, 1); tb <- matrix(rpois(r * cc, 12) + sample(0:8, r * cc, TRUE), r, cc)
  a <- unclass(assocstats(tb)); ct <- a$chisq_tests
  vals <- c(ct[1, 1], ct[2, 1], ct[1, 2], ct[1, 3], ct[2, 3], if (r == 2 && cc == 2) a$phi else NaN, a$contingency, a$cramer)
  for (q in 1:8) if (is.finite(vals[q])) add("as", c(r, cc, as.vector(t(tb)), q - 1), vals[q])
  k <- sample(2:5, 1); kt <- matrix(rpois(k * k, 5), k, k) + diag(sample(8:20, k, TRUE)); if (rep %% 2 == 0) wt <- "Fleiss-Cohen" else wt <- "Equal-Spacing"
  kp <- Kappa(kt, weights = wt); kv <- c(kp$Unweighted, kp$Weighted)
  for (q in 1:4) add("kp", c(k, as.numeric(wt == "Fleiss-Cohen"), as.vector(t(kt)), q - 1), kv[q])
  n1 <- sample(5:25, 1); n2 <- sample(5:25, 1); x <- round(rnorm(n1, 0.5, 1.2), 2); y <- round(rnorm(n2, 0, 1), 2)
  sm <- c(cohens_d(x, y)$Cohens_d, hedges_g(x, y)$Hedges_g, glass_delta(x, y)$Glass_delta_adjusted, rank_biserial(x, y)$r_rank_biserial)
  for (q in 1:4) add("smd", c(n1, n2, x, y, q - 1), sm[q])
  lev <- sample(c(0.8, 0.9, 0.95), 1)
  cd <- cohens_d(x, y, ci = lev); hg <- hedges_g(x, y, ci = lev); cv <- c(cd$CI_low, cd$CI_high, hg$CI_low, hg$CI_high)
  for (q in 1:4) cases[[length(cases) + 1]] <- case("smdci", c(n1, n2, x, y, lev, q - 1), cv[q], rel = 2e-5, abs = 2e-6)
  G <- sample(2:4, 1); sz <- sample(4:12, G, TRUE); yy <- round(rnorm(sum(sz), rep(seq_len(G) * 0.4, sz), 1.2), 2); g <- factor(rep(seq_len(G), sz))
  m <- aov(yy ~ g)
  ef <- suppressMessages(c(eta_squared(m)$Eta2[1], omega_squared(m)$Omega2[1], epsilon_squared(m)$Epsilon2[1]))
  for (q in 1:3) add("aov", c(G, sz, yy, q - 1), ef[q])
}
emit("vcdeffect", c("vcd", "effectsize"), list(cases))
