# PMCMRplus: siegelTukeyTest without ties (exact two-sided p). Args: (n1, n2, what 0 W 1 p, x[n1], y[n2]).
suppressMessages(library(PMCMRplus))
cases <- list()
set.seed(20262340)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("sk", args, want, rel = 1e-9, abs = 1e-12)
for (rep in 1:30) {
  n1 <- sample(4:12, 1); n2 <- sample(4:12, 1); x <- rnorm(n1); y <- rnorm(n2, 0, runif(1, 0.5, 2))
  r <- siegelTukeyTest(x, y)
  add(c(n1, n2, 0, x, y), unname(r$statistic)); add(c(n1, n2, 1, x, y), r$p.value)
}
emit("pmcmr_st", "PMCMRplus", list(cases))
