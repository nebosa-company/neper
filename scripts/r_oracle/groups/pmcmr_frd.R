# PMCMRplus: frdAllPairsNemenyiTest, frdAllPairsConoverTest (single-step and none). Args: (n, k, kind, i, j, y[n * k] row-major): kind 0 Nemenyi statistic, 1 Nemenyi p, 2 Conover
# single-step statistic, 3 Conover single-step p, 4 Conover t, 5 Conover unadjusted p; (i, j) the 0-based row and column of the result table (i > j).
suppressMessages(library(PMCMRplus))
cases <- list()
set.seed(20262315)
add <- function(args, want, abs = 1e-12) cases[[length(cases) + 1]] <<- case("fr", args, want, rel = 1e-8, abs = abs)
for (rep in 1:10) {
  k <- sample(3:5, 1); n <- sample(5:12, 1)
  y <- matrix(round(rnorm(n * k) + rep(seq_len(k) * runif(1, 0, 0.5), each = n), if (rep %% 3 == 0) 1 else 4), n, k)
  grp <- factor(rep(1:k, each = n)); blk <- factor(rep(1:n, k))
  nm <- suppressWarnings(frdAllPairsNemenyiTest(as.vector(y), grp, blk))
  cs <- suppressWarnings(frdAllPairsConoverTest(as.vector(y), grp, blk, p.adjust.method = "single-step"))
  cn <- suppressWarnings(frdAllPairsConoverTest(as.vector(y), grp, blk, p.adjust.method = "none"))
  for (i in 2:k) for (j in 1:(i - 1)) {
    a <- function(kind) c(n, k, kind, i - 1, j - 1, as.vector(t(y)))
    add(a(0), nm$statistic[i - 1, j]); add(a(1), nm$p.value[i - 1, j], abs = 1e-7)
    add(a(2), cs$statistic[i - 1, j]); add(a(3), cs$p.value[i - 1, j], abs = 1e-7)
    add(a(4), cn$statistic[i - 1, j]); add(a(5), cn$p.value[i - 1, j])
  }
}
emit("pmcmr_frd", "PMCMRplus", list(cases))
