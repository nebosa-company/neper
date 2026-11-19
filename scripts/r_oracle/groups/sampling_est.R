# sampling: Hajekestimator (total and mean), ratioest, inclusionprobastrata and HTstrata. Args: (kind, n, N, Tx, i, y[n], x[n], pik_or_strata[n], nh...): kind 0 Hajek total, 1 Hajek mean, 2 ratioest,
# 3 inclusionprobastrata (pik i; the strata vector in the fourth block, nh after it), 4 HTstrata (pik block, strata block).
suppressMessages(library(sampling))
cases <- list()
set.seed(20262327)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("es", args, want, rel = 1e-10, abs = 1e-12)
for (rep in 1:20) {
  n <- sample(10:40, 1); N <- n * sample(3:8, 1); y <- round(rnorm(n, 20, 5), 3); x <- round(runif(n, 1, 9), 3); pik <- round(runif(n, 0.1, 0.9), 3)
  H <- sample(2:4, 1); strata <- sample(1:H, n, replace = TRUE); strata[1:H] <- 1:H
  nh <- sample(2:6, H, replace = TRUE); Tx <- round(sum(x) * 3, 3)
  pa <- c(0, n, N, Tx, 0, y, x, pik, strata, nh)
  pa[1] <- 0; add(pa, as.numeric(suppressWarnings(Hajekestimator(y, pik, N = N, type = "total"))))
  pa[1] <- 1; add(pa, as.numeric(suppressWarnings(Hajekestimator(y, pik, N = NULL, type = "mean"))))
  pa[1] <- 2; add(pa, ratioest(y, x, Tx, pik))
  pk <- suppressWarnings(inclusionprobastrata(strata, nh))
  for (i in seq(1, n, by = 5)) { pa[1] <- 3; pa[5] <- i - 1; add(pa, pk[i]) }
  pa[1] <- 4; add(pa, HTstrata(y, pik, strata))
}
emit("sampling_est", "sampling", list(cases))
