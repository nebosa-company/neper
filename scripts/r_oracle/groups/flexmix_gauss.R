# flexmix: Gaussian regression mixture (FLXMRglm gaussian) from a given initial clustering. Args: (n, p, k, what, idx, x row-major (p columns, intercept first),
# y, init cluster 1-based): what 0 logLik, 1 iterations, 2 components kept, 3 prior[idx], 4 coef[idx] (component-major), 5 sigma[idx], 6 cluster[idx] (1-based).
suppressMessages(library(flexmix))
cases <- list()
set.seed(20261601)
one <- function(n, k, beta, sg, pr, flipfrac = 0.2) {
  z <- sample(seq_len(k), n, TRUE, pr)
  x1 <- runif(n, -2, 2)
  y <- vapply(seq_len(n), function(i) beta[z[i], 1] + beta[z[i], 2] * x1[i] + rnorm(1, 0, sg[z[i]]), 0)
  init <- z
  fl <- sample(n, round(flipfrac * n)); init[fl] <- sample(seq_len(k), length(fl), TRUE)
  fit <- flexmix(y ~ x1, k = k, cluster = init)
  kk <- fit@k
  prm <- parameters(fit)
  flat <- c(as.vector(rbind(1, x1)), y, init)
  hdr <- function(what, idx) c(n, 2, k, what, idx, flat)
  add <- function(what, idx, v, rel = 1e-5, abs = 1e-8) cases[[length(cases) + 1]] <<- case("f", hdr(what, idx), v, rel = rel, abs = abs)
  add(0, 0, as.numeric(logLik(fit)))
  add(1, 0, fit@iter, 0, 0)
  add(2, 0, kk, 0, 0)
  for (j in seq_len(kk)) add(3, j - 1, fit@prior[j])
  for (j in seq_len(kk)) { add(4, (j - 1) * 2, prm[1, j]); add(4, (j - 1) * 2 + 1, prm[2, j]); add(5, j - 1, prm[3, j]) }
  cl <- fit@cluster
  for (i in seq_len(n)) add(6, i - 1, cl[i], 0, 0)
}
one(120, 2, rbind(c(0, 2), c(3, -1.5)), c(0.5, 0.7), c(0.5, 0.5))
one(150, 3, rbind(c(0, 2), c(3, -1.5), c(-2, 0.5)), c(0.4, 0.6, 0.5), c(0.4, 0.3, 0.3))
one(90, 2, rbind(c(1, 1), c(1, -1)), c(0.3, 0.3), c(0.6, 0.4))
# the random start: flexmix(y ~ x1, k = k) after set.seed(seed); args (n, 2, k, what, idx, seed, x row-major, y) under "fs", what as above
oneseed <- function(n, k, beta, sg, pr, seed) {
  set.seed(seed)
  z <- sample(seq_len(k), n, TRUE, pr)
  x1 <- runif(n, -2, 2)
  y <- vapply(seq_len(n), function(i) beta[z[i], 1] + beta[z[i], 2] * x1[i] + rnorm(1, 0, sg[z[i]]), 0)
  set.seed(seed + 1)
  fit <- tryCatch(flexmix(y ~ x1, k = k), error = function(e) NULL)
  if (is.null(fit)) return(invisible(NULL))
  kk <- fit@k; prm <- parameters(fit)
  flat <- c(seed + 1, as.vector(rbind(1, x1)), y)
  hdr <- function(what, idx) c(n, 2, k, what, idx, flat)
  addf <- function(what, idx, v, rel = 1e-5, abs = 1e-8) cases[[length(cases) + 1]] <<- case("fs", hdr(what, idx), v, rel = rel, abs = abs)
  addf(0, 0, as.numeric(logLik(fit))); addf(1, 0, fit@iter, 0, 0); addf(2, 0, kk, 0, 0)
  for (j in seq_len(kk)) addf(3, j - 1, fit@prior[j])
  for (j in seq_len(kk)) { addf(4, (j - 1) * 2, prm[1, j]); addf(4, (j - 1) * 2 + 1, prm[2, j]); addf(5, j - 1, prm[3, j]) }
  cl <- fit@cluster
  for (i in seq_len(n)) addf(6, i - 1, cl[i], 0, 0)
}
oneseed(100, 2, rbind(c(0, 2), c(3, -1.5)), c(0.5, 0.7), c(0.5, 0.5), 11)
oneseed(120, 2, rbind(c(1, 1), c(-1, 2)), c(0.4, 0.4), c(0.5, 0.5), 22)
oneseed(150, 3, rbind(c(0, 2), c(3, -1.5), c(-2, 0.5)), c(0.4, 0.6, 0.5), c(0.4, 0.3, 0.3), 33)
emit("flexmix_gauss", "flexmix", list(cases))
