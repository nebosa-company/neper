# fdrtool::fdrtool for p values: eta0, the fndr cutoff, censored count, and the q values and local fdr of every p value.
#   args: (n, p[n])  fn "eta0" "cutoff" "ncens" "q_sum" "q_w" "l_sum" "l_w" (sum and position-weighted sum)
suppressMessages(library(fdrtool))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-10)
set.seed(20261116)
for (rep in 1:30) {
  n <- sample(60:400, 1); frac <- runif(1, 0.05, 0.5)
  p <- c(runif(round(n * (1 - frac))), rbeta(n - round(n * (1 - frac)), 0.3, 4))
  p <- pmin(1, pmax(0.001, if (rep %% 2 == 0) round(p, 3) else p))
  r <- suppressWarnings(fdrtool(p, statistic = "pvalue", plot = FALSE, verbose = FALSE))
  a <- c(n, p)
  add("eta0", a, r$param[1, 3]); add("cutoff", a, r$param[1, 1]); add("ncens", a, r$param[1, 2])
  add("q_sum", a, sum(r$qval)); add("q_w", a, sum(seq_len(n) * r$qval)); add("l_sum", a, sum(r$lfdr)); add("l_w", a, sum(seq_len(n) * r$lfdr))
}
emit("fdrtool", "fdrtool", list(cases))
