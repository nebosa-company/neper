# posterior, second half. Chain-major draws (nchain, n, x...) for "rb" "rbn" (rhat_basic split / not, no extra), "sd_ess" "sd_mcse", "essq"/"mcseq" (extra: prob),
# "zs" (z_scale of the flat draws, sum of i * z_i), "s_mean" "s_median" "s_sd" "s_mad" "s_q5" "s_q95" "s_rhat" "s_essb" "s_esst" (summarise_draws),
# and pareto_smooth of a vector (S, x, tail 0 both 1 right 2 left, r_eff or -1): "ps_k" "ps_min" "ps_thr" "ps_rate" "ps_x" (sum of i * smoothed_i / S)
suppressMessages(library(posterior))
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261302)
for (rep in 1:12) {
  nc <- sample(1:3, 1); n <- sample(c(40, 60), 1); phi <- runif(1, -0.3, 0.9)
  x <- sapply(seq_len(nc), function(k) as.vector(arima.sim(list(ar = phi), n)) + (rep %% 3) * 0.5 * k)
  if (rep %% 4 == 0) x <- exp(x / 2)
  if (rep %% 5 == 0) x <- round(x * 2) / 2
  x <- matrix(x, n, nc); a <- c(nc, n, as.vector(x)); pr <- sample(c(0.05, 0.25, 0.5, 0.9, 0.99), 1)
  s <- summarise_draws(as_draws_array(array(x, c(n, nc, 1))))
  nm <- c("s_mean", "s_median", "s_sd", "s_mad", "s_q5", "s_q95", "s_rhat", "s_essb", "s_esst")
  for (k in 1:9) add(nm[k], a, s[[k + 1]])
}
for (rep in 1:25) {
  S <- sample(c(100, 200, 400), 1); x <- switch(rep %% 3 + 1, rt(S, 2), exp(rnorm(S)), rnorm(S) + 2 * rexp(S)); tl <- sample(0:2, 1); re <- if (rep %% 2) -1 else runif(1, 0.3, 1)
  r <- suppressWarnings(pareto_smooth(x, tail = c("both", "right", "left")[tl + 1], r_eff = if (re > 0) re else NULL, return_k = TRUE, extra_diags = TRUE, verbose = FALSE))
  a <- c(S, x, tl, re); d <- r$diagnostics
  add("ps_k", a, d$khat); add("ps_min", a, d$min_ss); add("ps_thr", a, d$khat_threshold); add("ps_rate", a, d$convergence_rate); add("ps_x", a, sum(seq_len(S) * r$x) / S)
}
emit("posterior3", "posterior", list(cases))
