# PMCMRplus: kwManyOneDunnTest (two-sided, p.adjust.method none and holm). Args: (n, k, kind, j, x[n], group labels 1..k [n]): kind 0 the z statistic, 1 the unadjusted p, 2 the Holm-adjusted p of
# comparison j (1-based, group j + 1 against group 1); kinds 3, 4, 5 the same three for kwManyOneConoverTest.
suppressMessages(library(PMCMRplus))
cases <- list()
set.seed(20262318)
add <- function(args, want, abs = 1e-12) cases[[length(cases) + 1]] <<- case("mo", args, want, rel = 1e-8, abs = abs)
for (rep in 1:12) {
  k <- sample(3:6, 1); sz <- sample(4:9, k, replace = TRUE); n <- sum(sz); g <- factor(rep(1:k, sz))
  x <- round(rnorm(n) + as.numeric(g) * runif(1, 0, 0.6), if (rep %% 3 == 0) 0 else 4)
  cn <- suppressWarnings(kwManyOneConoverTest(x, g, p.adjust.method = "none")); ch <- suppressWarnings(kwManyOneConoverTest(x, g, p.adjust.method = "holm"))
  nn <- suppressWarnings(kwManyOneDunnTest(x, g, p.adjust.method = "none"))
  hh <- suppressWarnings(kwManyOneDunnTest(x, g, p.adjust.method = "holm"))
  for (j in 1:(k - 1)) {
    a <- function(kind) c(n, k, kind, j, x, as.numeric(g))
    add(a(0), nn$statistic[j, 1]); add(a(1), nn$p.value[j, 1]); add(a(2), hh$p.value[j, 1])
    add(a(3), cn$statistic[j, 1]); add(a(4), cn$p.value[j, 1]); add(a(5), ch$p.value[j, 1])
  }
}
# kwManyOneDunnTest single-step (kind 6, p of comparison j): unequal group sizes, so the correlations are sqrt(n_i n_j / ((n_i + n_0)(n_j + n_0))), integrated exactly here (R: Monte Carlo, 1e-3); kind 6 here.
for (rep in 1:12) {
  k <- sample(3:6, 1); sz <- sample(4:9, k, replace = TRUE); n <- sum(sz); g <- factor(rep(1:k, sz))
  x <- round(rnorm(n) + as.numeric(g) * runif(1, 0, 0.6), 4)
  ss <- suppressWarnings(kwManyOneDunnTest(x, g, p.adjust.method = "single-step"))
  for (j in 1:(k - 1)) add(c(n, k, 6, j, x, as.numeric(g)), ss$p.value[j, 1], abs = 3e-3)
}
emit("pmcmr_many", "PMCMRplus", list(cases))
