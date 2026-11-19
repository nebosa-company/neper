# PMCMRplus: vanWaerdenAllPairsTest. Args: (n, k, kind, i, j, x[n], group labels 1..k [n]): kind 0 the t statistic, 1 the unadjusted p, 2 the single-step Tukey p of cell (row i, column j), i > j (0-based).
suppressMessages(library(PMCMRplus))
cases <- list()
set.seed(20262316)
add <- function(args, want, abs = 1e-12) cases[[length(cases) + 1]] <<- case("vw", args, want, rel = 1e-8, abs = abs)
for (rep in 1:10) {
  k <- sample(3:5, 1); sz <- sample(4:9, k, replace = TRUE); n <- sum(sz); g <- factor(rep(1:k, sz))
  x <- round(rnorm(n) + as.numeric(g) * runif(1, 0, 0.6), if (rep %% 3 == 0) 0 else 4)
  nn <- suppressWarnings(vanWaerdenAllPairsTest(x, g, p.adjust.method = "none"))
  ss <- suppressWarnings(vanWaerdenAllPairsTest(x, g, p.adjust.method = "single-step"))
  for (i in 2:k) for (j in 1:(i - 1)) {
    a <- function(kind) c(n, k, kind, i - 1, j - 1, x, as.numeric(g))
    add(a(0), nn$statistic[i - 1, j]); add(a(1), nn$p.value[i - 1, j]); add(a(2), ss$p.value[i - 1, j], abs = 1e-7)
  }
}
emit("pmcmr_vdw", "PMCMRplus", list(cases))
