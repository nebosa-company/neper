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
# Poisson mixtures from a given start: args (n, 2, k, what, idx, x row-major, y, init) under "fp"
onepois <- function(n, k, beta, pr, flipfrac = 0.15) {
  z <- sample(seq_len(k), n, TRUE, pr)
  x1 <- runif(n, -1, 1)
  y <- vapply(seq_len(n), function(i) rpois(1, exp(beta[z[i], 1] + beta[z[i], 2] * x1[i])), 0)
  init <- z; fl <- sample(n, round(flipfrac * n)); init[fl] <- sample(seq_len(k), length(fl), TRUE)
  fit <- tryCatch(flexmix(y ~ x1, k = k, cluster = init, model = FLXMRglm(family = "poisson")), error = function(e) NULL)
  if (is.null(fit)) return(invisible(NULL))
  kk <- fit@k; prm <- parameters(fit)
  flat <- c(as.vector(rbind(1, x1)), y, init)
  hdr <- function(what, idx) c(n, 2, k, what, idx, flat)
  addf <- function(what, idx, v, rel = 1e-5, abs = 1e-8) cases[[length(cases) + 1]] <<- case("fp", hdr(what, idx), v, rel = rel, abs = abs)
  addf(0, 0, as.numeric(logLik(fit))); addf(1, 0, fit@iter, 0, 0); addf(2, 0, kk, 0, 0)
  for (j in seq_len(kk)) addf(3, j - 1, fit@prior[j])
  for (j in seq_len(kk)) { addf(4, (j - 1) * 2, prm[1, j]); addf(4, (j - 1) * 2 + 1, prm[2, j]) }
  cl <- fit@cluster
  for (i in seq_len(n)) addf(6, i - 1, cl[i], 0, 0)
}
onepois(150, 2, rbind(c(1, 1.5), c(2.5, -1.2)), c(0.5, 0.5))
onepois(200, 2, rbind(c(0.5, 1), c(2, 0.8)), c(0.4, 0.6))
onepois(240, 3, rbind(c(0.3, 1.2), c(1.8, -1), c(3, 0.3)), c(0.3, 0.3, 0.4))
# stepFlexmix: set.seed(seed); stepFlexmix(y ~ x1, k = 2:3, nrep = 3); args (n, 2, k, what, idx, seed, x row-major, y) under "st"; what 0 the best logLik, 1 logLiks[idx], 3 prior[idx], 4 coef[idx]
onestep <- function(n, beta, sg, pr, seed) {
  k <- length(pr)
  set.seed(seed)
  z <- sample(seq_len(k), n, TRUE, pr)
  x1 <- runif(n, -2, 2)
  y <- vapply(seq_len(n), function(i) beta[z[i], 1] + beta[z[i], 2] * x1[i] + rnorm(1, 0, sg[z[i]]), 0)
  set.seed(seed + 7)
  st <- stepFlexmix(y ~ x1, k = 2:3, nrep = 3, verbose = FALSE)
  flat <- c(seed + 7, as.vector(rbind(1, x1)), y)
  for (kk in c(2, 3)) {
    fit <- st@models[[as.character(kk)]]
    prm <- parameters(fit); ll <- st@logLiks[as.character(kk), ]
    hdr <- function(what, idx) c(n, 2, kk, what, idx, flat)
    adds <- function(what, idx, v) cases[[length(cases) + 1]] <<- case("st", hdr(what, idx), v, rel = 1e-5, abs = 1e-8)
    adds(0, 0, as.numeric(logLik(fit)))
    for (m in seq_along(ll)) if (is.finite(ll[m])) adds(1, m - 1, ll[m])
    for (j in seq_len(fit@k)) adds(3, j - 1, fit@prior[j])
    for (j in seq_len(fit@k)) { adds(4, (j - 1) * 2, prm[1, j]); adds(4, (j - 1) * 2 + 1, prm[2, j]) }
  }
}
onestep(120, rbind(c(0, 2), c(3, -1.5)), c(0.5, 0.7), c(0.5, 0.5), 5)
onestep(150, rbind(c(1, 1), c(-1, 2)), c(0.4, 0.4), c(0.5, 0.5), 6)
emit("flexmix_gauss", "flexmix", list(cases))
