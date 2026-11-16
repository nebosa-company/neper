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
# loo_compare of two models: ("cmp_d" "cmp_se"): args (S, N, ll_a, ll_b); the elpd difference and its standard error of model b against a (b better = positive)
for (rep in 1:15) {
  S <- sample(c(300, 600), 1); N <- sample(8:25, 1); y <- rnorm(N)
  mk <- function(mu0, sd0) { mu <- rnorm(S, mu0, 0.2); sg <- sd0 * exp(0.1 * rnorm(S)); sapply(seq_len(N), function(i) dnorm(y[i], mu, sg, log = TRUE)) }
  la <- mk(0, 1); lb <- mk(0.3, 1.2); cm <- suppressWarnings(loo_compare(loo(la), loo(lb)))
  a <- c(S, N, as.vector(la), as.vector(lb)); rn <- rownames(cm)
  # model order in the table: the better first; report b minus a with the sign of that order
  ea <- loo(la)$estimates["elpd_loo", 1]; eb <- loo(lb)$estimates["elpd_loo", 1]; dd <- eb - ea
  add("cmp_d", a, dd); add("cmp_se", a, cm[2, "se_diff"])
}
emit("loo", "loo", list(cases))
