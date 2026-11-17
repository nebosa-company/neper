# loo, importance-sampling methods and predictive metrics.
#   "is_*": loo(ll, r_eff, is_method = "tis" or "sis"): (S, N, method 1 tis 2 sis, r_eff, ll obs-major): "is_elpd" "is_se" "is_mcse" (sum of mcse_elpd_loo) "is_neff" (sum of n_eff)
#   "pk_*": pareto_k_table of loo(ll): (S, N, ll): "pk_c1" "pk_c2" "pk_c3" (counts), "pk_ne1" (min n_eff of the good class), "pk_ids" (length of pareto_k_ids), "mcse_loo"
#   "pm_*": loo_predictive_metric(x, y, ll, metric): (S, N, ll, x [N * S obs-major], y, metric 0 mae 1 rmse 2 mse 3 acc 4 balanced_acc): "pm_est" "pm_se"
suppressMessages(library(loo))
cases <- list()
add <- function(fn, args, want, rel = 1e-8, ab = 1e-10) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = ab)
set.seed(20261501)
for (rep in 1:4) {
  S <- 100; N <- sample(5:8, 1); mu <- rnorm(S); sg <- 1 + 0.3 * rnorm(S)^2; y <- rnorm(N) + (if (rep %% 2 == 0) rt(N, 2) else 0)
  ll <- sapply(seq_len(N), function(i) dnorm(y[i], mu, sg, log = TRUE)); re <- runif(1, 0.3, 1)
  for (m in 1:2) {
    l <- suppressWarnings(loo(ll, r_eff = re, is_method = c("tis", "sis")[m])); a <- c(S, N, m, re, as.vector(ll))
    add("is_elpd", a, l$estimates["elpd_loo", 1]); add("is_se", a, l$estimates["elpd_loo", 2]); add("is_mcse", a, sum(l$pointwise[, "mcse_elpd_loo"])); add("is_neff", a, sum(l$diagnostics$n_eff))
  }
}
for (rep in 1:4) {
  S <- 100; N <- sample(6:9, 1); mu <- rnorm(S); sg <- 1 + 0.3 * rnorm(S)^2; y <- rnorm(N, 0, 0.5); y[1:2] <- c(2.5, -3) * (rep %% 3) * 0.6
  ll <- sapply(seq_len(N), function(i) dnorm(y[i], mu, sg, log = TRUE)); a <- c(S, N, as.vector(ll))
  l <- suppressWarnings(loo(ll)); pt <- suppressWarnings(pareto_k_table(l)); add("pk_c1", a, pt[1, "Count"]); add("pk_c2", a, pt[2, "Count"]); add("pk_c3", a, pt[3, "Count"]); add("pk_ne1", a, pt[1, "Min. n_eff"])
  add("pk_ids", a, length(pareto_k_ids(l))); add("mcse_loo", a, mcse_loo(l))
}
for (rep in 1:2) {
  S <- 400; N <- 5; mu <- rnorm(S, 0, 0.5); sg <- 1 + 0.2 * rnorm(S)^2; y <- rnorm(N)
  ll <- sapply(seq_len(N), function(i) dnorm(y[i], mu, sg, log = TRUE)); a <- c(S, N, as.vector(ll))
  l <- suppressWarnings(loo(ll)); pt <- suppressWarnings(pareto_k_table(l)); add("pk_c1", a, pt[1, "Count"]); add("pk_c2", a, pt[2, "Count"]); add("pk_c3", a, pt[3, "Count"]); add("pk_ne1", a, pt[1, "Min. n_eff"])
  add("pk_ids", a, length(pareto_k_ids(l))); add("mcse_loo", a, mcse_loo(l))
}
for (rep in 1:5) {
  S <- 100; N <- sample(6:9, 1); mu <- rnorm(S); sg <- 1 + 0.3 * rnorm(S)^2; metric <- c("mae", "rmse", "mse", "acc", "balanced_acc")[(rep - 1) %% 5 + 1]
  if (metric %in% c("acc", "balanced_acc")) {
    p <- plogis(rnorm(S, 0.3)); yv <- rbinom(N, 1, 0.5); yv[1:2] <- c(0, 1)
    ll <- sapply(seq_len(N), function(i) dbinom(yv[i], 1, p, log = TRUE)); x <- matrix(rep(p, N), S, N) * 0 + matrix(plogis(rnorm(S * N, 0.2)), S, N)
  } else {
    yv <- rnorm(N); ll <- sapply(seq_len(N), function(i) dnorm(yv[i], mu, sg, log = TRUE)); x <- matrix(rnorm(S * N, mu, sg), S, N)
  }
  mt <- (rep - 1) %% 5
  r <- suppressWarnings(loo_predictive_metric(x, yv, ll, metric = metric)); a <- c(S, N, as.vector(ll), as.vector(x), yv, mt)
  add("pm_est", a, r$estimate); add("pm_se", a, r$se)
}
emit("loo4", "loo", list(cases))
