# coin asymptotic tests: two-sample with rank, normal, median and raw scores, Kruskal-Wallis K-sample, Spearman.
#   args: (n, kind, K, y[n], g[n] 0-based group or x[n] for Spearman); kind 0 wilcox 1 normal 2 median 3 oneway 4 kruskal 5 spearman
#   fn "stat", "p"
suppressMessages(library(coin))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-11)
set.seed(20261218)
for (rep in 1:36) {
  n <- sample(12:60, 1); kind <- (rep - 1) %% 6; K <- if (kind == 4) sample(3:4, 1) else 2
  y <- round(rnorm(n), sample(1:2, 1)); g <- sample(0:(K - 1), n, TRUE); while (length(unique(g)) < K) g <- sample(0:(K - 1), n, TRUE)
  x <- round(rnorm(n), 1) + 0.3 * y
  d <- data.frame(y = y, g = factor(g), x = x)
  t <- switch(kind + 1, wilcox_test(y ~ g, d, distribution = "asymptotic"), normal_test(y ~ g, d, distribution = "asymptotic"), median_test(y ~ g, d, distribution = "asymptotic"),
    oneway_test(y ~ g, d, distribution = "asymptotic"), kruskal_test(y ~ g, d, distribution = "asymptotic"), spearman_test(y ~ x, d, distribution = "asymptotic"))
  a <- c(n, kind, K, y, if (kind == 5) x else g)
  add("stat", a, as.numeric(statistic(t))); add("p", a, as.numeric(pvalue(t)))
}
emit("coin", "coin", list(cases))
