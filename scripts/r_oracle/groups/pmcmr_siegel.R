# PMCMRplus: frdAllPairsSiegelTest (Siegel-Castellan; unadjusted and Holm). Args: (n, k, kind, i, j, y[n * k] row-major): kind 0 statistic, 1 unadjusted p, 2 Holm p of the cell (row i, column j), i > j (0-based).
suppressMessages(library(PMCMRplus))
cases <- list()
set.seed(20262345)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("sg", args, want, rel = 1e-9, abs = 1e-12)
for (rep in 1:12) {
  k <- sample(3:5, 1); n <- sample(6:12, 1)
  y <- matrix(round(rnorm(n * k) + rep(seq_len(k) * runif(1, 0, 0.5), each = n), if (rep %% 3 == 0) 1 else 4), n, k)
  grp <- factor(rep(1:k, each = n)); blk <- factor(rep(1:n, k))
  nn <- suppressWarnings(frdAllPairsSiegelTest(as.vector(y), grp, blk, p.adjust.method = "none")); hh <- suppressWarnings(frdAllPairsSiegelTest(as.vector(y), grp, blk, p.adjust.method = "holm"))
  for (i in 2:k) for (j in 1:(i - 1)) { a <- function(kind) c(n, k, kind, i - 1, j - 1, as.vector(t(y))); add(a(0), nn$statistic[i - 1, j]); add(a(1), nn$p.value[i - 1, j]); add(a(2), hh$p.value[i - 1, j]) }
}
emit("pmcmr_siegel", "PMCMRplus", list(cases))
