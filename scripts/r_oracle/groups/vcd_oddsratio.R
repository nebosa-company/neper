# vcd::oddsratio (loddsratio, no reference categories) on r by c by s tables: the log odds ratios and the variances (diagonal of vcov).
# Args: (r, c, s, cells[r c s] column-major, which): which 0 sum of the coefficients, 1 sum of index * coefficient, 2 sum of the variances,
# 3 sum of index * variance.
suppressMessages(library(vcd))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261235)
for (rep in 1:20) {
  r <- sample(2:3, 1); cc <- sample(2:3, 1); s <- sample(2:3, 1)
  tab <- array(sample(1:60, r * cc * s, replace = TRUE), c(r, cc, s))
  if (rep %% 4 == 0) tab[1] <- 0
  o <- loddsratio(tab)
  v <- diag(o$vcov); cf <- as.numeric(o$coefficients); w <- seq_along(cf)
  base <- c(r, cc, s, as.numeric(tab))
  add("or", c(base, 0), sum(cf)); add("or", c(base, 1), sum(w * cf))
  add("or", c(base, 2), sum(v)); add("or", c(base, 3), sum(w * v))
}
emit("vcd_oddsratio", "vcd", list(cases))
