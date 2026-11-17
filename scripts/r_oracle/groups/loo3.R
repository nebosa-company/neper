# loo, the rest (E_loo and model weights); layouts in loo2.R
suppressMessages(library(loo))
cases <- list()
add <- function(fn, args, want, rel = 1e-8, ab = 1e-10) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = ab)
mkll <- function(S, N, y, shift = 0, scale = 1) { mu <- rnorm(S, shift, 0.5); sg <- scale * (1 + 0.3 * rnorm(S)^2); sapply(seq_len(N), function(i) dnorm(y[i], mu, sg, log = TRUE)) }
set.seed(20261402)
for (rep in 1:12) {
  S <- sample(c(100, 200), 1); mu <- rnorm(S); sg <- 1 + 0.3 * rnorm(S)^2; y <- 2 * rnorm(1)
  ll <- dnorm(y, mu, sg, log = TRUE); x <- if (rep %% 2) mu else exp(mu / 2); re <- if (rep %% 3) 1 else runif(1, 0.3, 1); pr <- runif(1, 0.05, 0.95)
  ps <- suppressWarnings(psis(matrix(-ll, ncol = 1), r_eff = re)); a <- c(S, x, ll, re, pr)
  for (ty in c("mean", "variance", "sd")) { e <- suppressWarnings(E_loo(x, ps, type = ty)); nm <- c(mean = "mean", variance = "var", sd = "sd")[ty]; add(paste0("e_", nm), a, e$value); add(paste0("ek_", nm), a, e$pareto_k) }
  e <- suppressWarnings(E_loo(x, ps, type = "quantile", probs = pr)); add("e_q", a, e$value); add("ek_q", a, e$pareto_k)
}
for (rep in 1:25) {
  S <- 150; N <- sample(8:20, 1); K <- sample(2:4, 1); y <- rnorm(N) + (if (rep %% 3 == 0) rt(N, 3) else 0)
  lls <- lapply(seq_len(K), function(j) mkll(S, N, y, 0.2 * (j - 1) * rnorm(1), 1 + 0.15 * (j - 1)))
  lpd <- do.call(cbind, lapply(lls, function(l) suppressWarnings(loo(l))$pointwise[, "elpd_loo"])); seed <- sample(1:100000, 1); bbn <- 200; al <- sample(c(1, 2), 1)
  st <- tryCatch(as.vector(stacking_weights(lpd)), error = function(e) NULL); pb <- as.vector(pseudobma_weights(lpd, BB = FALSE))
  set.seed(seed); bb <- as.vector(pseudobma_weights(lpd, BB = TRUE, BB_n = bbn, alpha = al))
  for (j in seq_len(K)) { a <- c(N, K, as.vector(t(lpd)), j - 1, seed, bbn, al); if (!is.null(st)) add("st", a, st[j], 1e-6, 1e-8); add("pb", a, pb[j]); add("bb", a, bb[j]) }
}
emit("loo3", "loo", list(cases))
