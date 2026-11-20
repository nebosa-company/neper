# randomForest 4.7-1.2: classification and regression forests grown under set.seed, summarised by position-weighted checksums (sum of (i + 1) * value, NA and NaN skipped).
#   fn "qsort": args = values; want = checksum of R_qsort_I's index vector (sort.int(method = "quick", index.return = TRUE)$ix)
#   fn "rf": args = (sel, kind, n, p, ntree, mtry, nodesize, sampsize, replace, importance, localImp, nPerm, prox, maxnodes, nclass, seed, ntest, pvar, pfocus, use_classwt,
#                    npt, keep_inbag, testmode (0 none, 1 xtest, 2 xtest and ytest; xtest is Xnew), corr.bias, oob.prox, 0, 0, 0, classwt[nclass], cutoff[nclass], y[n],
#                    X (row-major n by p), Xnew (row-major ntest by p), ytest[ntest])
#   sel (classification): 0 last OOB error, 1 err.rate, 2 predicted, 3 votes, 4 oob.times, 5 MeanDecreaseAccuracy, 6 MeanDecreaseGini, 7 class importance, 8 importanceSD,
#       9 importance(type = 1), 10 importance(), 11 proximity, 12 localImportance, 13 predict, 14 predict(prob), 15 predict(vote, norm.votes = FALSE), 16 partialPlot y,
#       17 inbag, 18 partialPlot x, 19 predict(proximity), 20 predict(nodes), 21 predict(predict.all), 22 test predicted, 23 test votes, 24 test err.rate, 25 test proximity
#   sel (regression): 0 last mse, 1 mse, 2 predicted, 3 oob.times, 4 last rsq, 5 %IncMSE, 6 IncNodePurity, 7 importanceSD, 8 importance(type = 1), 9 importance(),
#       10 proximity, 11 localImportance, 12 predict, 13 partialPlot y, 14 inbag, 15 partialPlot x, 16 predict(proximity), 17 predict(nodes), 18 predict(predict.all), 19 test predicted, 20 test mse, 21 test rsq,
#       22 test proximity (R divides the package's answer by ntree once more)
suppressMessages(library(randomForest))
cases <- list()
cs <- function(v) { v <- as.numeric(v); ok <- !is.na(v); sum((seq_along(v) * v)[ok]) }
q8 <- function(v) round(v * 64) / 64
add <- function(fn, args, want, rel = 1e-9, abs = 1e-10) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)

set.seed(20261235 %% 100000)
for (rep in 1:40) {
  n <- sample(c(5, 8, 13, 30, 60, 120, 200), 1)
  v <- q8(sample(c(rnorm(n), rep(0.25, 3)), n)); if (rep %% 3 == 0) v <- sample(1:4, n, replace = TRUE)
  add("qsort", v, cs(sort.int(v, method = "quick", index.return = TRUE)$ix), rel = 0, abs = 0)
}

emit_rf <- function(kind, X, y, Xnew, ntree, mtry, nodesize, sampsize, replace, importance = FALSE, localImp = FALSE, nPerm = 1, prox = FALSE,
                    maxnodes = NULL, classwt = NULL, cutoff = NULL, keep.inbag = FALSE, npt = 10, pvar = 1, pfocus = 1, seed = 1, testmode = 0, corr.bias = FALSE, oob.prox = TRUE, ytest = NULL) {
  n <- nrow(X); p <- ncol(X); ntest <- nrow(Xnew)
  K <- if (kind == 0) nlevels(y) else 1
  colnames(X) <- colnames(Xnew) <- paste0("V", 1:p)
  args <- list(x = X, y = y, ntree = ntree, mtry = mtry, nodesize = nodesize, sampsize = sampsize, replace = replace, importance = importance, localImp = localImp,
               nPerm = nPerm, proximity = prox, oob.prox = oob.prox, keep.inbag = keep.inbag)
  if (kind == 1) args$corr.bias <- corr.bias
  if (testmode > 0) { args$xtest <- Xnew; args$keep.forest <- TRUE; if (testmode == 2) args$ytest <- ytest }
  if (!is.null(maxnodes)) args$maxnodes <- maxnodes
  if (!is.null(classwt)) args$classwt <- classwt
  if (!is.null(cutoff)) args$cutoff <- cutoff
  set.seed(seed)
  fit <- suppressWarnings(do.call(randomForest, args))
  p1 <- predict(fit, Xnew)
  if (kind == 0) { p2 <- predict(fit, Xnew, type = "prob"); p3 <- predict(fit, Xnew, type = "vote", norm.votes = FALSE) }
  pa <- list(fit, X, paste0("V", pvar), plot = FALSE, n.pt = npt)
  if (kind == 0) pa$which.class <- levels(y)[pfocus]
  pp <- suppressWarnings(do.call(partialPlot, pa))
  p4 <- predict(fit, Xnew, proximity = TRUE, nodes = TRUE); p5 <- predict(fit, Xnew, predict.all = TRUE)
  cw <- if (is.null(classwt)) rep(0, K) else classwt
  co <- if (is.null(cutoff)) rep(1 / K, K) else cutoff
  yv <- if (kind == 0) as.integer(y) else y
  head <- function(sel) c(sel, kind, n, p, ntree, mtry, nodesize, sampsize, replace, importance, localImp, nPerm, prox, if (is.null(maxnodes)) 0 else maxnodes, K, seed, ntest, pvar - 1,
                          pfocus, !is.null(classwt), npt, keep.inbag, testmode, corr.bias, oob.prox, 0, 0, 0)
  yt <- if (is.null(ytest)) rep(0, ntest) else if (kind == 0) as.integer(ytest) else ytest
  a <- function(sel) c(head(sel), cw, co, yv, as.vector(t(X)), as.vector(t(Xnew)), yt)
  w <- function(sel, want, rel = 1e-9, abs = 1e-10) add("rf", a(sel), want, rel, abs)
  if (kind == 0) {
    er <- fit$err.rate
    w(0, er[ntree, 1]); w(1, cs(as.vector(t(er))))
    w(2, cs(as.integer(fit$predicted)), 0, 0)
    w(3, cs(as.vector(t(unclass(fit$votes)))))
    w(4, cs(fit$oob.times), 0, 0)
    if (importance) {
      w(5, cs(fit$importance[, K + 1])); w(7, cs(fit$importance[, 1:K])); w(8, cs(fit$importanceSD))
      w(9, cs(importance(fit, type = 1, scale = TRUE))); w(10, cs(importance(fit, scale = TRUE)))
      w(6, cs(fit$importance[, K + 2]))
    } else w(6, cs(fit$importance[, 1]))
    if (prox) w(11, cs(fit$proximity))
    if (localImp) w(12, cs(fit$localImportance))
    if (keep.inbag) w(17, cs(fit$inbag), 0, 0)
    w(13, cs(as.integer(p1)), 0, 0); w(14, cs(as.vector(t(p2)))); w(15, cs(as.vector(t(p3))))
    w(16, cs(pp$y)); w(18, cs(pp$x))
    w(19, cs(p4$proximity)); w(20, cs(attr(p4, "nodes")), 0, 0); w(21, cs(match(p5$individual, levels(y))), 0, 0)
    if (testmode > 0) {
      w(22, cs(as.integer(fit$test$predicted)), 0, 0); w(23, cs(as.vector(t(unclass(fit$test$votes)))))
      if (testmode == 2) w(24, cs(as.vector(t(fit$test$err.rate))))
      if (prox) w(25, cs(fit$test$proximity))
    }
  } else {
    w(0, fit$mse[ntree]); w(1, cs(fit$mse)); w(2, cs(fit$predicted)); w(3, cs(fit$oob.times), 0, 0); w(4, fit$rsq[ntree])
    if (importance) {
      w(5, cs(fit$importance[, 1])); w(6, cs(fit$importance[, 2])); w(7, cs(fit$importanceSD))
      w(8, cs(importance(fit, type = 1, scale = TRUE))); w(9, cs(importance(fit, scale = TRUE)))
    } else w(6, cs(fit$importance[, 1]))
    if (prox) w(10, cs(fit$proximity))
    if (localImp) w(11, cs(fit$localImportance))
    if (keep.inbag) w(14, cs(fit$inbag), 0, 0)
    w(12, cs(p1)); w(13, cs(pp$y)); w(15, cs(pp$x))
    w(16, cs(p4$proximity)); w(17, cs(attr(p4, "nodes")), 0, 0); w(18, cs(p5$individual))
    if (testmode > 0) {
      w(19, cs(fit$test$predicted))
      if (testmode == 2) { w(20, cs(fit$test$mse)); w(21, fit$test$rsq[ntree]) }
      if (prox) w(22, cs(fit$test$proximity))
    }
  }
}

mk <- function(n, p, ntest) list(X = matrix(q8(runif(n * p)), n, p), Xnew = matrix(q8(runif(ntest * p)), ntest, p))
mkclass <- function(d, K, noise = 0.3) {
  s <- 3 * (d$X[, 1] > 0.5) + 2 * (d$X[, 2] > 0.4) + d$X[, ncol(d$X)] + rnorm(nrow(d$X)) * noise
  factor(as.integer(cut(s, quantile(s, seq(0, 1, length.out = K + 1)), include.lowest = TRUE)))
}
mkreg <- function(d, noise = 0.4) round(3 * (d$X[, 1] > 0.5) + 2 * d$X[, 2] + d$X[, ncol(d$X)]^2 + rnorm(nrow(d$X)) * noise, 6)

# classification
cls <- list(
  list(n = 40, p = 4, K = 2, ntree = 25, mtry = 2, nodesize = 1, ss = 40, rep = TRUE),
  list(n = 45, p = 5, K = 3, ntree = 20, mtry = 2, nodesize = 3, ss = 45, rep = TRUE, imp = TRUE),
  list(n = 50, p = 4, K = 2, ntree = 21, mtry = 3, nodesize = 1, ss = 32, rep = FALSE, imp = TRUE, prox = TRUE),
  list(n = 42, p = 6, K = 4, ntree = 18, mtry = 3, nodesize = 2, ss = 30, rep = TRUE, imp = TRUE, li = TRUE),
  list(n = 48, p = 3, K = 3, ntree = 9, mtry = 1, nodesize = 5, ss = 48, rep = TRUE, cw = TRUE),
  list(n = 44, p = 4, K = 3, ntree = 6, mtry = 4, nodesize = 1, ss = 44, rep = TRUE, co = TRUE, ki = TRUE),
  list(n = 40, p = 5, K = 2, ntree = 16, mtry = 2, nodesize = 1, ss = 25, rep = FALSE, mn = 6, imp = TRUE),
  list(n = 46, p = 4, K = 3, ntree = 4, mtry = 2, nodesize = 1, ss = 46, rep = TRUE, imp = TRUE, prox = TRUE, ki = TRUE),
  list(n = 55, p = 5, K = 2, ntree = 30, mtry = 5, nodesize = 4, ss = 55, rep = TRUE, imp = TRUE, li = TRUE, prox = TRUE),
  list(n = 38, p = 3, K = 5, ntree = 12, mtry = 2, nodesize = 1, ss = 38, rep = TRUE, imp = TRUE),
  list(n = 44, p = 4, K = 3, ntree = 15, mtry = 2, nodesize = 1, ss = 44, rep = TRUE, imp = TRUE, prox = TRUE, tm = 2, noob = TRUE),
  list(n = 50, p = 5, K = 2, ntree = 10, mtry = 2, nodesize = 2, ss = 50, rep = TRUE, tm = 1, prox = TRUE),
  list(n = 40, p = 3, K = 4, ntree = 8, mtry = 2, nodesize = 1, ss = 28, rep = FALSE, tm = 2, imp = TRUE, li = TRUE)
)
for (cf in cls) {
  d <- mk(cf$n, cf$p, 14); y <- mkclass(d, cf$K, noise = if (cf$K > 3) 0.6 else 0.3)
  cw <- if (isTRUE(cf$cw)) round(runif(cf$K, 0.5, 3), 2) else NULL
  co <- if (isTRUE(cf$co)) { z <- round(runif(cf$K, 0.2, 1), 2); round(z / sum(z) * 0.98, 4) } else NULL
  sd <- sample(1:1000000, 1)
  emit_rf(0, d$X, y, d$Xnew, cf$ntree, cf$mtry, cf$nodesize, cf$ss, cf$rep, isTRUE(cf$imp), isTRUE(cf$li), 1, isTRUE(cf$prox), cf$mn, cw, co, isTRUE(cf$ki),
          npt = sample(c(8, 12), 1), pvar = sample(1:cf$p, 1), pfocus = sample(1:cf$K, 1), seed = sd, testmode = if (is.null(cf$tm)) 0 else cf$tm,
          oob.prox = !isTRUE(cf$noob), ytest = factor(sample(levels(y), 14, replace = TRUE), levels = levels(y)))
}
# regression
rgs <- list(
  list(n = 40, p = 4, ntree = 25, mtry = 2, nodesize = 5, ss = 40, rep = TRUE),
  list(n = 45, p = 5, ntree = 20, mtry = 2, nodesize = 3, ss = 45, rep = TRUE, imp = TRUE),
  list(n = 50, p = 4, ntree = 21, mtry = 3, nodesize = 5, ss = 32, rep = FALSE, imp = TRUE, prox = TRUE, np = 3),
  list(n = 42, p = 6, ntree = 15, mtry = 2, nodesize = 2, ss = 30, rep = TRUE, imp = TRUE, li = TRUE, np = 2),
  list(n = 48, p = 3, ntree = 12, mtry = 3, nodesize = 8, ss = 48, rep = TRUE, ki = TRUE, mn = 5),
  list(n = 44, p = 4, ntree = 10, mtry = 1, nodesize = 1, ss = 44, rep = TRUE, imp = TRUE, prox = TRUE, ki = TRUE),
  list(n = 60, p = 5, ntree = 30, mtry = 5, nodesize = 5, ss = 60, rep = TRUE, imp = TRUE, li = TRUE, prox = TRUE),
  list(n = 36, p = 3, ntree = 8, mtry = 2, nodesize = 1, ss = 20, rep = FALSE, imp = TRUE, np = 2),
  list(n = 45, p = 4, ntree = 14, mtry = 2, nodesize = 4, ss = 45, rep = TRUE, imp = TRUE, prox = TRUE, tm = 2, cb = TRUE, noob = TRUE),
  list(n = 50, p = 5, ntree = 10, mtry = 3, nodesize = 5, ss = 50, rep = TRUE, tm = 1, prox = TRUE),
  list(n = 40, p = 3, ntree = 12, mtry = 2, nodesize = 3, ss = 28, rep = FALSE, tm = 2, cb = TRUE)
)
for (cf in rgs) {
  d <- mk(cf$n, cf$p, 14); y <- mkreg(d)
  sd <- sample(1:1000000, 1)
  emit_rf(1, d$X, y, d$Xnew, cf$ntree, cf$mtry, cf$nodesize, cf$ss, cf$rep, isTRUE(cf$imp), isTRUE(cf$li), if (is.null(cf$np)) 1 else cf$np, isTRUE(cf$prox), cf$mn, NULL, NULL,
          isTRUE(cf$ki), npt = sample(c(8, 12), 1), pvar = sample(1:cf$p, 1), seed = sd, testmode = if (is.null(cf$tm)) 0 else cf$tm, corr.bias = isTRUE(cf$cb),
          oob.prox = !isTRUE(cf$noob), ytest = mkreg(list(X = d$Xnew)))
}
emit("randomforest", "randomForest", list(cases))
