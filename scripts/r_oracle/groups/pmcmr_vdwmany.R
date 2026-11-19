# PMCMRplus: vanWaerdenManyOneTest (two-sided, none and holm). Args: (n, k, kind, j, x[n], group labels 1..k [n]): kind 0 the signed t statistic, 1 the unadjusted p, 2 the Holm p of comparison j (1-based).
suppressMessages(library(PMCMRplus))
cases <- list()
set.seed(20262320)
add <- function(args, want, abs = 1e-12) cases[[length(cases) + 1]] <<- case("vm", args, want, rel = 1e-8, abs = abs)
for (rep in 1:12) {
  k <- sample(3:6, 1); sz <- sample(4:9, k, replace = TRUE); n <- sum(sz); g <- factor(rep(1:k, sz))
  x <- round(rnorm(n) + as.numeric(g) * runif(1, 0, 0.6), if (rep %% 3 == 0) 0 else 4)
  nn <- suppressWarnings(vanWaerdenManyOneTest(x, g, p.adjust.method = "none")); hh <- suppressWarnings(vanWaerdenManyOneTest(x, g, p.adjust.method = "holm"))
  for (j in 1:(k - 1)) {
    a <- function(kind) c(n, k, kind, j, x, as.numeric(g))
    add(a(0), nn$statistic[j, 1]); add(a(1), nn$p.value[j, 1]); add(a(2), hh$p.value[j, 1])
  }
}
# vanWaerdenManyOneTest single-step (kind 3: p of comparison j, R's pmvt Monte Carlo, error about 1e-3).
for (rep in 1:10) {
  k <- sample(3:5, 1); sz <- sample(5:9, k, replace = TRUE); n <- sum(sz); g <- factor(rep(1:k, sz))
  x <- round(rnorm(n) + as.numeric(g) * runif(1, 0, 0.6), 4)
  vs <- suppressWarnings(vanWaerdenManyOneTest(x, g, p.adjust.method = "single-step"))
  for (j in 1:(k - 1)) add(c(n, k, 3, j, x, as.numeric(g)), vs$p.value[j, 1], abs = 4e-3)
}
emit("pmcmr_vdwmany", "PMCMRplus", list(cases))
