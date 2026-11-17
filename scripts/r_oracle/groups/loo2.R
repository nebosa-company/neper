# loo, the rest. Draws of a log-likelihood matrix are chain-major within each observation block.
#   "l_*": loo(ll, r_eff = relative_eff(exp(ll), chain_id)): (nchain, n, N, ll obs-major): "l_elpd" "l_se" "l_p" "l_sep" "l_mcse" (sum of mcse_elpd_loo) "l_k" (sum of finite k) "l_neff" (sum of psis n_eff) "l_reff" (sum of r_eff)
#   "w_*": waic: "w_elpd" "w_se" "w_p" "w_sep"
#   "cmp_d" / "cmp_se" model j (extra arg j, 0-based) of loo_compare over K models: (S, N, K, ll model-major..., j)
#   "e_*": E_loo of one observation: (S, x[S], ll[S], r_eff, prob): "e_mean" "e_var" "e_sd" "e_q" and their Pareto k "ek_mean" "ek_var" "ek_sd" "ek_q"
#   "st" stacking weight j, "pb" pseudo-BMA weight j, "bb" pseudo-BMA BB weight j: (N, K, lpd row-major, j, seed, BB_n, alpha)
suppressMessages(library(loo))
cases <- list()
add <- function(fn, args, want, rel = 1e-8, ab = 1e-10) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = ab)
mkll <- function(S, N, y, shift = 0, scale = 1) { mu <- rnorm(S, shift, 0.5); sg <- scale * (1 + 0.3 * rnorm(S)^2); sapply(seq_len(N), function(i) dnorm(y[i], mu, sg, log = TRUE)) }
set.seed(20261401)
for (rep in 1:8) {
  nc <- sample(2:3, 1); n <- sample(c(20, 30), 1); S <- nc * n; N <- sample(5:7, 1); y <- rnorm(N) + (if (rep %% 3 == 0) rt(N, 2) else 0)
  mu <- as.vector(sapply(seq_len(nc), function(k) as.vector(arima.sim(list(ar = 0.6), n)) + 0.3 * k)); sg <- 1 + 0.3 * rnorm(S)^2
  ll <- sapply(seq_len(N), function(i) dnorm(y[i], mu, sg, log = TRUE)); a <- c(nc, n, N, as.vector(ll))
  re <- suppressWarnings(relative_eff(exp(ll), chain_id = rep(seq_len(nc), each = n)))
  l <- suppressWarnings(loo(ll, r_eff = re)); w <- suppressWarnings(waic(ll)); k <- l$diagnostics$pareto_k
  add("l_elpd", a, l$estimates["elpd_loo", 1]); add("l_se", a, l$estimates["elpd_loo", 2]); add("l_p", a, l$estimates["p_loo", 1]); add("l_sep", a, l$estimates["p_loo", 2])
  add("l_mcse", a, sum(l$pointwise[, "mcse_elpd_loo"])); add("l_k", a, sum(k[is.finite(k)])); add("l_neff", a, sum(l$diagnostics$n_eff)); add("l_reff", a, sum(re))
  add("w_elpd", a, w$estimates["elpd_waic", 1]); add("w_se", a, w$estimates["elpd_waic", 2]); add("w_p", a, w$estimates["p_waic", 1]); add("w_sep", a, w$estimates["p_waic", 2])
}
for (rep in 1:6) {
  S <- 60; N <- 6; K <- 3; y <- rnorm(N)
  lls <- lapply(seq_len(K), function(j) mkll(S, N, y, 0.15 * j, 1 + 0.1 * j)); cm <- suppressWarnings(loo_compare(lapply(lls, loo)))
  for (j in seq_len(K)) { ix <- which(cm$model == paste0("model", j)); a <- c(S, N, K, unlist(lapply(lls, as.vector)), j - 1); add("cmp_d", a, cm$elpd_diff[ix]); add("cmp_se", a, cm$se_diff[ix]) }
}
emit("loo2", "loo", list(cases))
