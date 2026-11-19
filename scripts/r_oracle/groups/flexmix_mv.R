# flexmix multivariate clustering drivers FLXMCmvnorm (full / diagonal) and FLXMCmvbinary. Case "mv" args: (n, d, k, model, what, idx, seed, y row-major (n*d), init 1-based (n)),
# model 0 full mvnorm, 1 diagonal mvnorm, 2 mvbinary; seed > 0 means the random start after set.seed(seed) (init then ignored);
# what 0 logLik, 1 iterations, 2 components kept, 3 prior[idx], 4 center[idx] (component-major), 5 cov[idx] (component, row, column), 6 cluster[idx] (1-based), 7 AIC, 8 BIC, 9 ICL.
suppressMessages(library(flexmix))
cases <- list()
set.seed(20261901)
onemv <- function(n, d, k, model, seed = 0, flipfrac = 0.2) {
  pr <- rep(1 / k, k)
  z <- sample(seq_len(k), n, TRUE, pr)
  if (model < 2) {
    mu <- matrix(rnorm(k * d, 0, 3), k, d)
    y <- mu[z, , drop = FALSE] + matrix(rnorm(n * d), n, d) * rep(c(0.8, 1.2, 0.6)[seq_len(d)], each = n)
    if (model == 0) y[, 2] <- y[, 2] + 0.5 * y[, 1]
  } else {
    pm <- matrix(runif(k * d, 0.1, 0.9), k, d)
    y <- matrix(0, n, d)
    for (i in seq_len(n)) y[i, ] <- rbinom(d, 1, pm[z[i], ])
  }
  init <- z; fl <- sample(n, round(flipfrac * n)); init[fl] <- sample(seq_len(k), length(fl), TRUE)
  mod <- if (model == 0) FLXMCmvnorm(diagonal = FALSE) else if (model == 1) FLXMCmvnorm(diagonal = TRUE) else FLXMCmvbinary()
  if (seed > 0) { set.seed(seed); fit <- tryCatch(flexmix(y ~ 1, k = k, model = mod), error = function(e) NULL) }
  else fit <- tryCatch(flexmix(y ~ 1, k = k, cluster = init, model = mod), error = function(e) NULL)
  if (is.null(fit)) return(invisible(NULL))
  kk <- fit@k
  flat <- c(as.vector(t(y)), init)
  hdr <- function(what, idx) c(n, d, k, model, what, idx, seed, flat)
  add <- function(what, idx, v, rel = 1e-9, abs = 1e-9) cases[[length(cases) + 1]] <<- case("mv", hdr(what, idx), v, rel = rel, abs = abs)
  add(0, 0, as.numeric(logLik(fit))); add(1, 0, fit@iter, 0, 0); add(2, 0, kk, 0, 0)
  add(7, 0, AIC(fit)); add(8, 0, BIC(fit)); add(9, 0, ICL(fit))
  w <- function(v) sum(seq_along(v) * v)
  add(3, 0, w(fit@prior))
  cen <- unlist(lapply(seq_len(kk), function(j) fit@components[[j]][[1]]@parameters$center))
  add(4, 0, w(cen))
  if (model < 2) add(5, 0, w(unlist(lapply(seq_len(kk), function(j) as.vector(t(fit@components[[j]][[1]]@parameters$cov))))))
  add(6, 0, w(fit@cluster), 0, 0)
}
onemv(150, 2, 2, 0)
onemv(180, 3, 3, 0)
onemv(150, 2, 2, 1)
onemv(180, 3, 3, 1)
onemv(150, 2, 2, 0, seed = 5)
onemv(160, 3, 2, 1, seed = 8)
onemv(200, 5, 2, 2)
onemv(240, 6, 3, 2)
onemv(200, 5, 2, 2, seed = 9)
emit("flexmix_mv", "flexmix", list(cases))
