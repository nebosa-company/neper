# PMCMRplus: kwAllPairsDunnTest, kwAllPairsConoverTest (single-step and holm), kwAllPairsNemenyiTest (Tukey).
#   args: (n, k, x[n]..., group labels 1..k [n]...)   fn "dz" "dp" "dpholm" (Dunn z, p, holm-adjusted p), "ct" "cp" "cptukey" "cpholm" (Conover), "nq" "np" (Nemenyi)
#   each is the sum over the pairs (i > j, column-major lower triangle) of value * pair position
suppressMessages(library(PMCMRplus))
cases <- list()
add <- function(fn, args, want, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = abs)
w <- function(m) { v <- m[lower.tri(m, diag = TRUE)]; v <- as.vector(m)[!is.na(as.vector(m))]; v }
set.seed(20261226)
for (rep in 1:14) {
  k <- sample(3:5, 1); sz <- sample(4:9, k, replace = TRUE); n <- sum(sz); g <- factor(rep(1:k, sz))
  x <- round(rnorm(n) + as.numeric(g) * runif(1, 0, 0.6), if (rep %% 3 == 0) 0 else 4)
  a <- c(n, k, x, as.numeric(g))
  sw <- function(m) { v <- as.vector(m); v <- v[!is.na(v)]; sum(v * seq_along(v)) }
  d <- suppressWarnings(kwAllPairsDunnTest(x, g, p.adjust.method = "none")); dh <- suppressWarnings(kwAllPairsDunnTest(x, g, p.adjust.method = "holm"))
  add("dz", a, sw(d$statistic)); add("dp", a, sw(d$p.value)); add("dpholm", a, sw(dh$p.value))
  cs <- suppressWarnings(kwAllPairsConoverTest(x, g, p.adjust.method = "single-step")); cn <- suppressWarnings(kwAllPairsConoverTest(x, g, p.adjust.method = "none")); ch <- suppressWarnings(kwAllPairsConoverTest(x, g, p.adjust.method = "holm"))
  add("ct", a, sw(cn$statistic)); add("cp", a, sw(cn$p.value)); add("cptukey", a, sw(cs$p.value), abs = 1e-7); add("cpholm", a, sw(ch$p.value))
  nm <- suppressWarnings(kwAllPairsNemenyiTest(x, g, dist = "Tukey"))
  add("nq", a, sw(nm$statistic)); add("np", a, sw(nm$p.value), abs = 1e-7)
}
for (rep in 1:30) {
  m <- sample(2:25, 1); p <- round(runif(m)^2, 4) + 1e-4; p <- pmin(p, 1); meth <- c("holm", "hochberg", "hommel", "bonferroni", "BH", "BY")
  for (mi in 0:5) { adj <- p.adjust(p, meth[mi + 1]); add("padj", c(mi, m, 0, p), sum(adj * seq_along(adj))) }
}
emit("pmcmr", "PMCMRplus", list(cases))
