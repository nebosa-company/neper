# vcd::woolf_test on 2 by 2 by k tables. Args: (k, cells[4 k] column-major, j); j 0 the statistic, 1 the p value.
suppressMessages(library(vcd))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261234)
for (rep in 1:20) {
  k <- sample(2:5, 1)
  tab <- array(sample(0:40, 4 * k, replace = TRUE, prob = c(0.02, rep(0.98 / 40, 40))), c(2, 2, k))
  if (rep %% 4 == 0) tab <- array(sample(1:40, 4 * k, replace = TRUE), c(2, 2, k))
  if (any(apply(tab, 3, function(s) all(s == 0)))) next
  w <- woolf_test(tab)
  add("w", c(k, as.numeric(tab), 0), as.numeric(w$statistic), 1e-8, 1e-10)
  add("w", c(k, as.numeric(tab), 1), as.numeric(w$p.value), 1e-7, 1e-12)
}
emit("vcd_woolf", "vcd", list(cases))
