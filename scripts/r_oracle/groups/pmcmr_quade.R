# PMCMRplus: quadeAllPairsTest (p.adjust.method = "none"), TDist and Normal. Args: (b, k, kind, i, j, y[b * k] row-major): kind 0 t statistic, 1 t p, 2 z statistic, 3 z p of cell (row i, column j), i > j (0-based).
suppressMessages(library(PMCMRplus))
cases <- list()
set.seed(20262317)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("qd", args, want, rel = 1e-8, abs = 1e-12)
for (rep in 1:10) {
  k <- sample(3:5, 1); b <- sample(5:12, 1)
  y <- matrix(round(rnorm(b * k) * runif(b, 0.5, 2) + rep(seq_len(k) * runif(1, 0, 0.5), each = b), if (rep %% 3 == 0) 1 else 4), b, k)
  tt <- suppressWarnings(quadeAllPairsTest(y, dist = "TDist", p.adjust.method = "none"))
  zz <- suppressWarnings(quadeAllPairsTest(y, dist = "Normal", p.adjust.method = "none"))
  for (i in 2:k) for (j in 1:(i - 1)) {
    a <- function(kind) c(b, k, kind, i - 1, j - 1, as.vector(t(y)))
    add(a(0), tt$statistic[i - 1, j]); add(a(1), tt$p.value[i - 1, j]); add(a(2), zz$statistic[i - 1, j]); add(a(3), zz$p.value[i - 1, j])
  }
}
emit("pmcmr_quade", "PMCMRplus", list(cases))
