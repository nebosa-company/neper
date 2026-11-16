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
#   cutoff.method: fn "c_eta0" "c_cutoff" "c_ncens" "c_q_sum" "c_q_w" "c_l_sum" "c_l_w", args (n, statistic 0 pvalue 1 normal, method 1 pct0 2 locfdr, pct0, x[n])
for (rep in 1:30) {
  n <- sample(300:1200, 1); st <- rep %% 2; frac <- runif(1, 0.05, 0.4); pct <- round(runif(1, 0.55, 0.9), 2)
  meth <- if (st == 0) 1 else (rep %% 3) %/% 1 %% 2 + 1
  if (st == 0) { na <- round(n * frac); x <- c(runif(n - na), rbeta(na, 0.3, 4)); x <- pmin(1, pmax(0.001, round(x, 4))) }
  else { na <- round(n * frac); x <- c(rnorm(n - na, 0, 1.1), rnorm(na, 3, 1)); x <- round(x, 4) }
  r <- tryCatch(suppressWarnings(fdrtool(x, statistic = if (st == 0) "pvalue" else "normal", cutoff.method = if (meth == 1) "pct0" else "locfdr", pct0 = pct, plot = FALSE, verbose = FALSE)), error = function(e) NULL)
  if (is.null(r)) next
  a <- c(n, st, meth, pct, x)
  add("c_eta0", a, r$param[1, 3]); add("c_cutoff", a, r$param[1, 1]); add("c_ncens", a, r$param[1, 2])
  add("c_q_sum", a, sum(r$qval)); add("c_q_w", a, sum(seq_along(x) * r$qval)); add("c_l_sum", a, sum(r$lfdr)); add("c_l_w", a, sum(seq_along(x) * r$lfdr))
}
#   statistic = "correlation": args (n, x[n]) fn "r_eta0" "r_cutoff" "r_ncens" "r_kappa" "r_kappase" "r_eta0se" "r_q_sum" "r_q_w" "r_l_sum" "r_l_w"
for (rep in 1:30) {
  n <- sample(300:1500, 1); kap <- sample(c(15, 30, 60, 120), 1); frac <- runif(1, 0.05, 0.3)
  na <- round(n * frac)
  z <- c(tanh(rnorm(n - na, 0, 1 / sqrt(kap - 1.5))), tanh(rnorm(na, sample(c(-1, 1), 1) * runif(1, 0.5, 1.2), 1 / sqrt(kap - 1.5))))
  r <- tryCatch(suppressWarnings(fdrtool(z, statistic = "correlation", plot = FALSE, verbose = FALSE)), error = function(e) NULL)
  if (is.null(r)) next
  a <- c(n, z)
  add("r_eta0", a, r$param[1, 3]); add("r_cutoff", a, r$param[1, 1]); add("r_ncens", a, r$param[1, 2])
  add("r_kappa", a, r$param[1, 5]); cases[[length(cases) + 1]] <- case("r_kappase", a, r$param[1, 6], rel = 1e-5, abs = 1e-8); add("r_eta0se", a, r$param[1, 4])
  add("r_q_sum", a, sum(r$qval)); add("r_q_w", a, sum(seq_along(z) * r$qval)); add("r_l_sum", a, sum(r$lfdr)); add("r_l_w", a, sum(seq_along(z) * r$lfdr))
}
emit("fdrtool", "fdrtool", list(cases))
