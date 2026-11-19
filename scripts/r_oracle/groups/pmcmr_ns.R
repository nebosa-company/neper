# PMCMRplus: normalScoresManyOneTest on data without ties (ties are broken at random by the package). PMCMRplus takes the expected normal order statistics from SuppDists::normOrder, an
# approximation good to about 6e-5, so the comparison is at 5e-4 relative. Args: (n, k, kind, j, x[n], group labels 1..k [n]): kind 0 the t statistic, 1 the unadjusted p, 2 the Holm p.
suppressMessages(library(PMCMRplus))
cases <- list()
set.seed(20262346)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("nsc", args, want, rel = 5e-4, abs = 1e-4)
for (rep in 1:12) {
  k <- sample(3:5, 1); sz <- sample(5:9, k, replace = TRUE); n <- sum(sz); g <- factor(rep(1:k, sz))
  x <- rnorm(n) + as.numeric(g) * runif(1, 0, 0.6)
  nn <- suppressWarnings(normalScoresManyOneTest(x, g, p.adjust.method = "none")); hh <- suppressWarnings(normalScoresManyOneTest(x, g, p.adjust.method = "holm"))
  for (j in 1:(k - 1)) { a <- function(kind) c(n, k, kind, j, x, as.numeric(g)); add(a(0), nn$statistic[j, 1]); add(a(1), nn$p.value[j, 1]); add(a(2), hh$p.value[j, 1]) }
}
emit("pmcmr_ns", "PMCMRplus", list(cases))
