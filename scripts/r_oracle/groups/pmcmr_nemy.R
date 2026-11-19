# PMCMRplus: frdManyOneNemenyiTest (two-sided, single-step with R's pmvnorm Monte Carlo, absolute error 1e-3). Args: (n, k, kind, j, y[n * k] row-major): kind 0 statistic, 1 p of comparison j (1-based).
suppressMessages(library(PMCMRplus))
cases <- list()
set.seed(20262341)
add <- function(args, want, abs = 1e-12) cases[[length(cases) + 1]] <<- case("fn", args, want, rel = 1e-9, abs = abs)
for (rep in 1:15) {
  k <- sample(3:5, 1); n <- sample(6:12, 1)
  y <- matrix(round(rnorm(n * k) + rep(seq_len(k) * runif(1, 0, 0.5), each = n), 4), n, k)
  grp <- factor(rep(1:k, each = n)); blk <- factor(rep(1:n, k))
  r <- suppressWarnings(frdManyOneNemenyiTest(as.vector(y), grp, blk))
  for (j in 1:(k - 1)) { a <- function(kind) c(n, k, kind, j, as.vector(t(y))); add(a(0), r$statistic[j, 1]); add(a(1), r$p.value[j, 1], abs = 3e-3) }
}
emit("pmcmr_nemy", "PMCMRplus", list(cases))
