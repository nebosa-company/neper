# PMCMRplus: vanWaerdenManyOneTest (two-sided, none and holm). Args: (n, k, kind, j, x[n], group labels 1..k [n]): kind 0 the signed t statistic, 1 the unadjusted p, 2 the Holm p of comparison j (1-based).
suppressMessages(library(PMCMRplus))
cases <- list()
set.seed(20262320)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("vm", args, want, rel = 1e-8, abs = 1e-12)
for (rep in 1:12) {
  k <- sample(3:6, 1); sz <- sample(4:9, k, replace = TRUE); n <- sum(sz); g <- factor(rep(1:k, sz))
  x <- round(rnorm(n) + as.numeric(g) * runif(1, 0, 0.6), if (rep %% 3 == 0) 0 else 4)
  nn <- suppressWarnings(vanWaerdenManyOneTest(x, g, p.adjust.method = "none")); hh <- suppressWarnings(vanWaerdenManyOneTest(x, g, p.adjust.method = "holm"))
  for (j in 1:(k - 1)) {
    a <- function(kind) c(n, k, kind, j, x, as.numeric(g))
    add(a(0), nn$statistic[j, 1]); add(a(1), nn$p.value[j, 1]); add(a(2), hh$p.value[j, 1])
  }
}
emit("pmcmr_vdwmany", "PMCMRplus", list(cases))
