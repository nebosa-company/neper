# rcompanion beyond the effect sizes: pairwiseMedianTest, pairwiseNominalIndependence and groupwiseMean (with its bootstrap intervals).
#   "pmed"  (k, n, digits, method, x[n], g[n] 0-based, q): q < m the signif'ed p of pair q (pairs (1,2), (1,3) ..), q >= m the adjusted p of pair q - m; method 5 = "fdr", 1 bonferroni, 2 holm
#   "pnom"  (r, c, compare, digits, method, gcorr, yates, q, table[r c] row-major): q = 10 pair + column; columns 0 p.Fisher 1 p.Gtest 2 p.Chisq 3 Cramer.V
#           4 Chisq 5 df 6 G 7 p.adj.Fisher 8 p.adj.Gtest 9 p.adj.Chisq; compare 0 row 1 column; gcorr 0 none 1 williams 2 yates
#   "gmean" (k, n, trim, conf, R, flags, digits, seed, q, x[n], g[n] 0-based): q = 13 group + column: 0 n 1 Mean 2 Boot.mean 3 Trad.lower 4 Trad.upper 5 Basic.lower
#           6 Basic.upper 7 Normal.lower 8 Normal.upper 9 Percentile.lower 10 Percentile.upper 11 Bca.lower 12 Bca.upper; flags bit 0 boot 1 basic 2 normal 3 percentile 4 bca 5 traditional
suppressMessages(library(rcompanion))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) if (length(want) == 1 && is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261203)
codes <- c(none = 0, bonferroni = 1, holm = 2, hochberg = 3, hommel = 4, fdr = 5, BY = 6)
for (rep in 1:14) {
  k <- sample(3:5, 1); sz <- sample(6:15, k, TRUE); g <- rep(0:(k - 1), sz); n <- sum(g >= 0)
  x <- round(rnorm(n, g * 0.5, 1), if (rep %% 2) 0 else 2); meth <- c("fdr", "bonferroni", "holm")[rep %% 3 + 1]
  z <- tryCatch(suppressWarnings(pairwiseMedianTest(x, factor(g), digits = 4, method = meth)), error = function(e) NULL); if (is.null(z)) next
  m <- nrow(z); a <- c(k, n, 4, codes[[meth]], x, g)
  for (j in seq_len(m)) { add("pmed", c(a, j - 1), as.numeric(z$p.value[j])); add("pmed", c(a, m + j - 1), as.numeric(z$p.adjust[j])) }
}
for (rep in 1:18) {
  r <- sample(2:4, 1); c <- sample(2:4, 1); compare <- rep %% 2; tb <- matrix(sample(1:15, r * c, TRUE), r, c)
  gc <- if (compare == 0 && c == 2 && rep %% 3 == 0) 2 else rep %% 2; meth <- c("fdr", "holm")[(rep %/% 2) %% 2 + 1]; digits <- c(3, 10)[(rep %/% 3) %% 2 + 1]
  z <- tryCatch(suppressWarnings(pairwiseNominalIndependence(tb, compare = c("row", "column")[compare + 1], fisher = TRUE, gtest = TRUE, chisq = TRUE, method = meth,
          correct = c("none", "williams", "yates")[gc + 1], yates = rep %% 4 == 0, stats = TRUE, cramer = TRUE, digits = digits)), error = function(e) NULL)
  if (is.null(z)) next
  a <- c(r, c, compare, digits, codes[[meth]], gc, as.numeric(rep %% 4 == 0), 0, tb)
  cols <- c("p.Fisher", "p.Gtest", "p.Chisq", "Cramer.V", "Chisq", "df", "G", "p.adj.Fisher", "p.adj.Gtest", "p.adj.Chisq")
  # the matrix is given row-major to Neper, column-major to R
  a[9:length(a)] <- as.vector(t(tb))
  for (j in seq_len(nrow(z))) for (cc in seq_along(cols)) { a2 <- a; a2[8] <- 10 * (j - 1) + cc - 1; add("pnom", a2, as.numeric(z[[cols[cc]]][j]), rel = 1e-8) }
}
for (rep in 1:10) {
  k <- sample(2:3, 1); sz <- sample(10:25, k, TRUE); g <- rep(0:(k - 1), sz); n <- sum(sz); x <- round(rlnorm(n, 2, 0.6), 2)
  trim <- if (rep %% 4 == 0) 0.1 else 0; R <- if (rep == 7) 15 else sample(c(100, 200), 1); flags <- c(1 + 2 + 4 + 8 + 16 + 32, 2 + 8 + 32, 4 + 16, 1 + 32, 2 + 4 + 8 + 16 + 32)[rep %% 5 + 1]
  conf <- sample(c(0.9, 0.95), 1); seed <- sample(1:1e6, 1)
  d <- data.frame(v = x, grp = factor(g))
  set.seed(seed)
  z <- tryCatch(suppressWarnings(groupwiseMean(v ~ grp, data = d, trim = trim, conf = conf, R = R, boot = bitwAnd(flags, 1) > 0, basic = bitwAnd(flags, 2) > 0, normal = bitwAnd(flags, 4) > 0,
          percentile = bitwAnd(flags, 8) > 0, bca = bitwAnd(flags, 16) > 0, traditional = bitwAnd(flags, 32) > 0, digits = 15)), error = function(e) NULL)
  if (is.null(z)) next
  cols <- c("n", "Mean", "Boot.mean", "Trad.lower", "Trad.upper", "Basic.lower", "Basic.upper", "Normal.lower", "Normal.upper", "Percentile.lower", "Percentile.upper", "Bca.lower", "Bca.upper")
  a <- c(k, n, trim, conf, R, flags, 15, seed, 0, x, g)
  for (j in seq_len(nrow(z))) for (cc in seq_along(cols)) if (cols[cc] %in% names(z)) { a2 <- a; a2[9] <- 13 * (j - 1) + cc - 1; add("gmean", a2, as.numeric(z[[cols[cc]]][j]), rel = 1e-8) }
}
emit("rcompanion_ext", c("rcompanion", "plyr", "boot"), list(cases))
