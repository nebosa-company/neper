# PMCMRplus: frdManyOneDemsarTest (two-sided, none and holm). Args: (n, k, kind, j, y[n * k] row-major): kind 0 the signed z statistic, 1 the unadjusted p, 2 the Holm p of comparison j (1-based, treatment j + 1 against treatment 1).
suppressMessages(library(PMCMRplus))
cases <- list()
set.seed(20262321)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("dm", args, want, rel = 1e-8, abs = 1e-12)
for (rep in 1:12) {
  k <- sample(3:6, 1); n <- sample(5:12, 1)
  y <- matrix(round(rnorm(n * k) + rep(seq_len(k) * runif(1, 0, 0.5), each = n), if (rep %% 3 == 0) 1 else 4), n, k)
  grp <- factor(rep(1:k, each = n)); blk <- factor(rep(1:n, k))
  nn <- suppressWarnings(frdManyOneDemsarTest(as.vector(y), grp, blk, p.adjust.method = "none"))
  hh <- suppressWarnings(frdManyOneDemsarTest(as.vector(y), grp, blk, p.adjust.method = "holm"))
  for (j in 1:(k - 1)) {
    a <- function(kind) c(n, k, kind, j, as.vector(t(y)))
    add(a(0), nn$statistic[j, 1]); add(a(1), nn$p.value[j, 1]); add(a(2), hh$p.value[j, 1])
  }
}
emit("pmcmr_demsar", "PMCMRplus", list(cases))
