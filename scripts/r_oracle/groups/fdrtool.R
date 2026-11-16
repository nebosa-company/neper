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
#   statistic = "normal": args (n, x[n]) fn "z_eta0" "z_cutoff" "z_ncens" "z_sd" "z_sdse" "z_eta0se" "z_q_sum" "z_q_w" "z_l_sum" "z_l_w"
for (rep in 1:30) {
  n <- sample(300:1500, 1); frac <- runif(1, 0.05, 0.4); s0 <- runif(1, 0.8, 1.5)
  na <- round(n * frac)
  z <- c(rnorm(n - na, 0, s0), rnorm(na, sample(c(-3, 3, 4), 1), 1))
  z <- if (rep %% 2 == 0) round(z, 3) else z
  r <- tryCatch(suppressWarnings(fdrtool(z, statistic = "normal", plot = FALSE, verbose = FALSE)), error = function(e) NULL)
  if (is.null(r)) next
  a <- c(n, z)
  add("z_eta0", a, r$param[1, 3]); add("z_cutoff", a, r$param[1, 1]); add("z_ncens", a, r$param[1, 2])
  # the standard error of the scale is a fourth-order difference quotient of a sum near 1e3 over a step of 1e-4: its roundoff is about 1e-8
  add("z_sd", a, r$param[1, 5]); cases[[length(cases) + 1]] <- case("z_sdse", a, r$param[1, 6], rel = 1e-6, abs = 1e-9); add("z_eta0se", a, r$param[1, 4])
  add("z_q_sum", a, sum(r$qval)); add("z_q_w", a, sum(seq_along(z) * r$qval)); add("z_l_sum", a, sum(r$lfdr)); add("z_l_w", a, sum(seq_along(z) * r$lfdr))
}
emit("fdrtool", "fdrtool", list(cases))
