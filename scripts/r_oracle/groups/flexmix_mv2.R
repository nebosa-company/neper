# flexmix multivariate drivers (FLXMCmvnorm full and diagonal, FLXMCmvbinary, FLXMCmvpois, FLXMCnorm1) under EM, CEM and SEM from R's random start, and stepFlexmix over them.
# The data are drawn here and again in the fixture from the seed (z <- sample(k, n, TRUE); the component parameters; then the rows). Case "mx" args (13 values):
# 0 seed, 1 n, 2 d, 3 k, 4 model (0 mvnorm full, 1 mvnorm diagonal, 2 mvbinary, 3 mvpois, 4 norm1), 5 classify (0 weighted, 1 CEM, 2 SEM), 6 mode (0 flexmix, 1 stepFlexmix k..k2),
# 7 k2, 8 nrep, 9 kq, 10 seed2, 11 what, 12 idx.
# what: 0 logLik, 1 iter, 2 k, 3 prior checksum, 4 center / lambda / mean checksum, 5 covariance (norm1: sd) checksum, 6 cluster checksum, 7 AIC, 8 BIC, 9 ICL, 10 posterior checksum, 15 stepFlexmix logLiks[idx].
suppressMessages(library(flexmix))
cases <- list()
cs <- function(v) sum(seq_along(v) * as.vector(v))

gen <- function(n, d, k, model) {
  z <- sample(seq_len(k), n, TRUE, rep(1 / k, k))
  if (model == 0 || model == 1 || model == 4) {
    mu <- matrix(rnorm(k * d, 0, 3), k, d)
    y <- mu[z, , drop = FALSE] + matrix(rnorm(n * d), n, d) * rep(c(0.8, 1.2, 0.6)[seq_len(d)], each = n)
    if (model == 0) y[, 2] <- y[, 2] + 0.5 * y[, 1]
  } else if (model == 2) {
    pm <- matrix(runif(k * d, 0.1, 0.9), k, d)
    y <- matrix(0, n, d)
    for (i in seq_len(n)) y[i, ] <- rbinom(d, 1, pm[z[i], ])
  } else {
    lam <- matrix(runif(k * d, 1, 8), k, d)
    y <- matrix(0, n, d)
    for (i in seq_len(n)) y[i, ] <- rpois(d, lam[z[i], ])
  }
  y
}

run <- function(seed, n, d, k, model, cls = 0, mode = 0, k2 = k, nrep = 3, seed2 = seed + 1) {
  set.seed(seed)
  y <- gen(n, d, k, model)
  set.seed(seed2)
  mod <- switch(model + 1, FLXMCmvnorm(diagonal = FALSE), FLXMCmvnorm(diagonal = TRUE), FLXMCmvbinary(), FLXMCmvpois(), FLXMCnorm1())
  if (model == 4) y <- as.vector(y)
  ctl <- list(classify = c("weighted", "CEM", "SEM")[cls + 1])
  kcur <- k
  hdr <- function(what, idx) c(seed, n, d, k, model, cls, mode, k2, nrep, kcur, seed2, what, idx)
  add <- function(what, idx, v, rel = 1e-9, abs = 1e-9) cases[[length(cases) + 1]] <<- case("mx", hdr(what, idx), v, rel = rel, abs = abs)
  describe <- function(fit) {
    kk <- fit@k
    add(0, 0, as.numeric(logLik(fit))); add(1, 0, fit@iter, 0, 0); add(2, 0, kk, 0, 0)
    add(7, 0, AIC(fit)); add(8, 0, BIC(fit)); add(9, 0, ICL(fit))
    add(3, 0, cs(fit@prior))
    pr <- function(j) fit@components[[j]][[1]]@parameters
    if (model == 3) add(4, 0, cs(unlist(lapply(seq_len(kk), function(j) pr(j)$lambda))))
    else if (model == 4) { add(4, 0, cs(unlist(lapply(seq_len(kk), function(j) pr(j)$mean)))); add(5, 0, cs(unlist(lapply(seq_len(kk), function(j) pr(j)$sd)))) }
    else add(4, 0, cs(unlist(lapply(seq_len(kk), function(j) pr(j)$center))))
    if (model < 2) add(5, 0, cs(unlist(lapply(seq_len(kk), function(j) as.vector(t(pr(j)$cov))))))
    add(6, 0, cs(fit@cluster), 0, 0)
    add(10, 0, cs(t(posterior(fit))))
  }
  if (mode == 0) {
    fit <- tryCatch(flexmix(y ~ 1, k = k, model = mod, control = ctl), error = function(e) NULL)
    if (is.null(fit)) return(invisible(NULL))
    describe(fit)
  } else {
    st <- tryCatch(stepFlexmix(y ~ 1, k = k:k2, nrep = nrep, model = mod, control = ctl, verbose = FALSE, drop = FALSE), error = function(e) NULL)
    if (is.null(st)) return(invisible(NULL))
    for (kk in k:k2) {
      fit <- st@models[[as.character(kk)]]
      if (is.null(fit)) next
      kcur <- kk
      ll <- st@logLiks[as.character(kk), ]
      for (m in seq_along(ll)) if (is.finite(ll[m])) add(15, m - 1, ll[m])
      describe(fit)
    }
  }
}

sd <- 700
for (model in 0:3) for (cls in 0:2) {
  d <- if (model == 3) 4 else if (model == 2) 5 else 3
  sd <- sd + 1; run(sd, 180, d, 3, model, cls)
  sd <- sd + 1; run(sd, 150, d, 2, model, cls, mode = 1, k2 = 3, nrep = 3)
}
for (cls in 0:2) { sd <- sd + 1; run(sd, 160, 1, 2, 4, cls); sd <- sd + 1; run(sd, 160, 1, 2, 4, cls, mode = 1, k2 = 3, nrep = 2) }
emit("flexmix_mv2", "flexmix", list(cases))
