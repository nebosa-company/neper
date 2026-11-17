# ashr: ash fits with a normal likelihood. args (n, kind, pointmass, nullbiased, nullweight, mode, mult, betahat[n], sebetahat[n], f, i)
#   kind 0 uniform 1 halfuniform 2 normal 3 +uniform 4 -uniform; f 0 loglik 1 logLR 2 NegativeProb 3 PositiveProb 4 lfsr 5 svalue 6 lfdr 7 qvalue 8 PosteriorMean 9 PosteriorSD 10 ncomp 11 pi[i] (pruned), 12 a[i] (uniform) or sd[i] (normal), 13 b[i]
suppressMessages(library(ashr))
cases <- list()
set.seed(20261116)
kinds <- c("uniform", "halfuniform", "normal", "+uniform", "-uniform")
for (rep in 1:30) {
  n <- sample(40:200, 1); sdv <- round(runif(n, 0.3, 1.5), 3)
  true <- ifelse(runif(n) < 0.6, 0, rnorm(n, 0, 2)); bh <- round(true + rnorm(n) * sdv, 4)
  kind <- (rep - 1) %% 5; fdr <- rep %% 3 != 0
  nw <- if (fdr) c(10, 5, 3)[sample(3, 1)] else 1
  md <- if (kind %in% c(3, 4)) 0 else 0
  fit <- suppressWarnings(if (fdr) ash(bh, sdv, mixcompdist = kinds[kind + 1], method = "fdr", nullweight = nw) else ash(bh, sdv, mixcompdist = kinds[kind + 1], method = "shrink"))
  res <- fit$result; g <- fit$fitted_g; kp <- g$pi > 1e-10; g$pi <- g$pi[kp] / sum(g$pi[kp]); if (kind == 2) g$sd <- g$sd[kp] else { g$a <- g$a[kp]; g$b <- g$b[kp] }
  base <- c(n, kind, as.numeric(fdr), as.numeric(fdr), nw, md, sqrt(2), bh, sdv)
  add <- function(f, i, v) cases[[length(cases) + 1]] <<- case("ash", c(base, f, i), as.numeric(v), rel = 1e-4, abs = 1e-5)
  add(0, 0, fit$loglik); add(1, 0, fit$logLR)
  cols <- c("NegativeProb", "PositiveProb", "lfsr", "svalue", "lfdr", "qvalue", "PosteriorMean", "PosteriorSD")
  for (ci in seq_along(cols)) for (i in sample(n, 8)) add(1 + ci, i - 1, res[[cols[ci]]][i])
  add(10, 0, length(g$pi))
  for (i in seq_along(g$pi)) {
    add(11, i - 1, g$pi[i])
    if (kind == 2) { add(12, i - 1, g$sd[i]); add(13, i - 1, 0) } else { add(12, i - 1, g$a[i]); add(13, i - 1, g$b[i]) }
  }
}
# the EM fit (optmethod = "mixEM", kind + 10): the same outputs
for (rep in 1:30) {
  n <- sample(40:200, 1); sdv <- round(runif(n, 0.3, 1.5), 3)
  true <- ifelse(runif(n) < 0.6, 0, rnorm(n, 0, 2)); bh <- round(true + rnorm(n) * sdv, 4)
  kind <- (rep - 1) %% 5; fdr <- rep %% 3 != 0
  nw <- if (fdr) c(10, 5, 3)[sample(3, 1)] else 1
  fit <- tryCatch(suppressWarnings(if (fdr) ash(bh, sdv, mixcompdist = kinds[kind + 1], method = "fdr", nullweight = nw, optmethod = "mixEM") else ash(bh, sdv, mixcompdist = kinds[kind + 1], method = "shrink", optmethod = "mixEM")), error = function(e) NULL); if (is.null(fit)) next
  res <- fit$result; g <- fit$fitted_g; kp <- g$pi > 1e-10
  base <- c(n, kind + 10, as.numeric(fdr), as.numeric(fdr), nw, 0, sqrt(2), bh, sdv)
  add <- function(f, i, v) cases[[length(cases) + 1]] <<- case("ash", c(base, f, i), as.numeric(v), rel = 1e-3, abs = 1e-4)
  add(0, 0, fit$loglik); add(1, 0, fit$logLR)
  # with a flat prior (shrink) the EM stops at a point along a flat ridge that depends on rounding: only the likelihood is compared there
  if (fdr) { cols <- c("NegativeProb", "PositiveProb", "lfsr", "svalue", "lfdr", "qvalue", "PosteriorMean", "PosteriorSD")
  for (ci in seq_along(cols)) for (i in sample(n, 8)) add(1 + ci, i - 1, res[[cols[ci]]][i]) }
}
# halfnormal mixtures (kind 5, mixSQP): the same outputs; g$sd is the component sd
for (rep in 1:20) {
  n <- sample(40:200, 1); sdv <- round(runif(n, 0.3, 1.5), 3)
  true <- ifelse(runif(n) < 0.6, 0, rnorm(n, 0, 2)); bh <- round(true + rnorm(n) * sdv, 4)
  fdr <- rep %% 3 != 0; nw <- if (fdr) c(10, 5, 3)[sample(3, 1)] else 1
  fit <- tryCatch(suppressWarnings(if (fdr) ash(bh, sdv, mixcompdist = "halfnormal", method = "fdr", nullweight = nw) else ash(bh, sdv, mixcompdist = "halfnormal", method = "shrink")), error = function(e) NULL); if (is.null(fit)) next
  res <- fit$result
  base <- c(n, 5, as.numeric(fdr), as.numeric(fdr), nw, 0, sqrt(2), bh, sdv)
  add <- function(f, i, v) cases[[length(cases) + 1]] <<- case("ash", c(base, f, i), as.numeric(v), rel = 1e-4, abs = 1e-5)
  add(0, 0, fit$loglik); add(1, 0, fit$logLR)
  cols <- c("NegativeProb", "PositiveProb", "lfsr", "svalue", "lfdr", "qvalue", "PosteriorMean", "PosteriorSD")
  for (ci in seq_along(cols)) for (i in sample(n, 8)) add(1 + ci, i - 1, res[[cols[ci]]][i])
}
# mode estimation (mode = NaN in the mode slot): uniform, halfuniform and normal mixtures with the pointmass prior; loglik, lfsr and PosteriorMean
for (rep in 1:20) {
  n <- sample(60:200, 1); sdv <- round(runif(n, 0.3, 1.5), 3)
  true <- ifelse(runif(n) < 0.5, 0.8, rnorm(n, 0.8, 2)); bh <- round(true + rnorm(n) * sdv, 4)
  kind <- c(0, 1, 2)[rep %% 3 + 1]; nw <- c(10, 5)[sample(2, 1)]
  fit <- tryCatch(suppressWarnings(ash(bh, sdv, mixcompdist = kinds[kind + 1], mode = "estimate", method = "fdr", nullweight = nw)), error = function(e) NULL); if (is.null(fit)) next
  res <- fit$result
  base <- c(n, kind, 1, 1, nw, NaN, sqrt(2), bh, sdv)
  add <- function(f, i, v) cases[[length(cases) + 1]] <<- case("ash", c(base, f, i), as.numeric(v), rel = 1e-3, abs = 1e-4)
  add(0, 0, fit$loglik)
  cols <- c("NegativeProb", "PositiveProb", "lfsr", "svalue", "lfdr", "qvalue", "PosteriorMean", "PosteriorSD")
  for (ci in c(3, 7)) for (i in sample(n, 6)) add(1 + ci, i - 1, res[[cols[ci]]][i])
}
emit("ashr", "ashr", list(cases))
