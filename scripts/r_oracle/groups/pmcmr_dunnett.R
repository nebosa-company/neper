# PMCMRplus: dunnettTest (two-sided; pDunnett is R's Monte Carlo pmvt, absolute error about 1e-3). Args: (n, k, kind, j, x[n], group labels 1..k [n]): kind 0 the t statistic, 1 the p value of comparison j.
suppressMessages(library(PMCMRplus))
cases <- list()
set.seed(20262343)
add <- function(args, want, abs = 1e-12) cases[[length(cases) + 1]] <<- case("du", args, want, rel = 1e-8, abs = abs)
for (rep in 1:12) {
  k <- sample(3:5, 1); sz <- sample(5:10, k, replace = TRUE); n <- sum(sz); g <- factor(rep(1:k, sz))
  x <- round(rnorm(n) + as.numeric(g) * runif(1, 0, 0.7), 4)
  r <- suppressWarnings(dunnettTest(x, g))
  for (j in 1:(k - 1)) { a <- function(kind) c(n, k, kind, j, x, as.numeric(g)); add(a(0), r$statistic[j, 1]); add(a(1), r$p.value[j, 1], abs = 4e-3) }
}
emit("pmcmr_dunnett", "PMCMRplus", list(cases))
