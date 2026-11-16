# loo: waic and loo (PSIS, r_eff = 1) totals of a log-likelihood matrix, and gpdfit.
#   args: (S, N, ll obs-major [N * S])   fn "waic_elpd" "waic_p" "loo_elpd" "loo_p" "loo_k" (sum of the Pareto k, finite part)
suppressMessages({library(loo); library(posterior)})
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-10)
set.seed(20261203)
for (rep in 1:25) {
  S <- sample(c(200, 500, 1000), 1); N <- sample(5:25, 1); mu <- rnorm(S); sg <- 1 + 0.3 * rnorm(S)^2; y <- rnorm(N) + (if (rep %% 3 == 0) rt(N, 2) else 0)
  ll <- sapply(seq_len(N), function(i) dnorm(y[i], mu, sg, log = TRUE)); a <- c(S, N, as.vector(ll))
  w <- suppressWarnings(waic(ll)); add("waic_elpd", a, w$estimates["elpd_waic", 1]); add("waic_p", a, w$estimates["p_waic", 1])
  l <- suppressWarnings(loo(ll)); add("loo_elpd", a, l$estimates["elpd_loo", 1]); add("loo_p", a, l$estimates["p_loo", 1]); k <- l$diagnostics$pareto_k; add("loo_k", a, sum(k[is.finite(k)]))
}
emit("loo", "loo", list(cases))
