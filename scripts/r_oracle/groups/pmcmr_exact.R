# PMCMRplus: frdAllPairsExactTest (exact (Eisinga et al.); unadjusted and Holm). Args: (n, k, kind, i, j, y[n * k] row-major): kind 0 statistic, 1 unadjusted p, 2 Holm p of the cell (row i, column j), i > j (0-based).
suppressMessages(library(PMCMRplus))
cases <- list()
set.seed(20262345)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("ex", args, want, rel = 1e-9, abs = 1e-12)
for (rep in 1:14) {
  k <- sample(3:5, 1); n <- sample(3:8, 1)
  y <- matrix(round(rnorm(n * k) + rep(seq_len(k) * runif(1, 0, 0.5), each = n), 4), n, k)
  grp <- factor(rep(1:k, each = n)); blk <- factor(rep(1:n, k))
  nn <- suppressWarnings(frdAllPairsExactTest(as.vector(y), grp, blk, p.adjust.method = "none")); hh <- suppressWarnings(frdAllPairsExactTest(as.vector(y), grp, blk, p.adjust.method = "holm"))
  for (i in 2:k) for (j in 1:(i - 1)) { a <- function(kind) c(n, k, kind, i - 1, j - 1, as.vector(t(y))); add(a(0), nn$statistic[i - 1, j]); add(a(1), nn$p.value[i - 1, j]); add(a(2), hh$p.value[i - 1, j]) }
}
emit("pmcmr_exact", "PMCMRplus", list(cases))
