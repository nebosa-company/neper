# caret: confusionMatrix of a two-class table (first level positive) and postResample.
#   args: (fn id, TP, FP, FN, TN) fn "cm" id 0 accuracy 1 kappa 2 lower 3 upper 4 NIR 5 p 6 mcnemar 7 sens 8 spec 9 ppv 10 npv 11 f1 12 prevalence 13 detection rate 14 detection prevalence 15 balanced
#   "pr": (id, n, pred[n], obs[n]) id 0 RMSE 1 Rsquared 2 MAE
suppressMessages(library(caret))
cases <- list()
add <- function(fn, args, want, tol = 1e-8) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = tol, abs = 1e-12)
set.seed(20261116)
for (rep in 1:40) {
  tp <- sample(5:150, 1); fp <- sample(1:80, 1); fn <- sample(1:80, 1); tn <- sample(5:150, 1)
  tb <- matrix(c(tp, fn, fp, tn), 2, dimnames = list(Prediction = c("a", "b"), Reference = c("a", "b")))
  cm <- confusionMatrix(as.table(tb))
  o <- cm$overall; b <- cm$byClass
  vals <- c(o[["Accuracy"]], o[["Kappa"]], o[["AccuracyLower"]], o[["AccuracyUpper"]], o[["AccuracyNull"]], o[["AccuracyPValue"]], o[["McnemarPValue"]],
            b[["Sensitivity"]], b[["Specificity"]], b[["Pos Pred Value"]], b[["Neg Pred Value"]], b[["F1"]], b[["Prevalence"]], b[["Detection Rate"]], b[["Detection Prevalence"]], b[["Balanced Accuracy"]])
  for (k in seq_along(vals)) add("cm", c(k - 1, tp, fp, fn, tn), vals[k], if (k == 6) 1e-6 else 1e-8)
}
for (rep in 1:20) {
  n <- sample(5:60, 1); obs <- rnorm(n, 5, 2); pred <- obs + rnorm(n, 0.2, 1)
  r <- postResample(pred, obs)
  for (k in 1:3) add("pr", c(k - 1, n, pred, obs), r[[k]])
}
# resampling indices (RNG): "rs" createResample (seed, n); "cf" createFolds(list = FALSE) (seed, k, n, class codes 1..); "gk" groupKFold (seed, k, m, n, group codes 1..m by first appearance), each answered as sum(position * value);
# "ts" createTimeSlices (n, initialWindow, horizon, fixedWindow, skip, id) id 0 slices 1 sum of training starts 2 training stops 3 test starts 4 test stops
for (rep in 1:25) {
  sd <- sample(1:100000, 1); n <- sample(5:80, 1)
  set.seed(sd); v <- createResample(seq_len(n), times = 1)[[1]]; add("rs", c(sd, n), sum(seq_along(v) * v), 1e-12)
  k <- sample(2:6, 1); nc <- sample(1:4, 1); n2 <- sample(10:70, 1); y <- sample(1:nc, n2, TRUE)
  set.seed(sd); f <- createFolds(factor(y), k = k, list = FALSE); add("cf", c(sd, k, n2, y), sum(seq_along(f) * f), 1e-12)
  m <- sample(3:12, 1); g <- sample(1:m, 25, TRUE); g <- match(g, unique(g)); mm <- max(g); kk <- sample(2:mm, 1)
  set.seed(sd); gf <- groupKFold(g, k = kk); tf <- integer(length(g)); for (i in seq_along(gf)) tf[setdiff(seq_along(g), gf[[i]])] <- i
  set.seed(sd); ff <- sample(kk, size = mm, replace = TRUE); add("gk", c(sd, kk, mm, length(g), g), sum(seq_along(g) * ff[g]), 1e-12)
  nn <- sample(12:60, 1); iw <- sample(3:8, 1); hz <- sample(1:4, 1); fx <- sample(c(TRUE, FALSE), 1); sk <- sample(0:3, 1)
  ts <- createTimeSlices(seq_len(nn), iw, hz, fx, sk)
  st <- c(length(ts$train), sum(sapply(ts$train, `[`, 1)), sum(sapply(ts$train, function(z) z[length(z)])), sum(sapply(ts$test, `[`, 1)), sum(sapply(ts$test, function(z) z[length(z)])))
  for (j in 0:4) add("ts", c(nn, iw, hz, as.numeric(fx), sk, j), st[j + 1], 1e-12)
}
# createDataPartition: "dp" (seed, p, groups, numeric 0/1, n, y[n]) as sum(position * selected); a factor y is given as codes 1.., a numeric y as its values
for (rep in 1:25) {
  sd <- sample(1:100000, 1); n <- sample(12:80, 1); pp <- sample(c(0.3, 0.5, 0.75, 0.8), 1); gg <- sample(2:6, 1)
  yc <- sample(1:sample(2:4, 1), n, TRUE); set.seed(sd); sel <- createDataPartition(factor(yc), times = 1, p = pp, list = FALSE)[, 1]
  mk <- numeric(n); mk[sel] <- 1; add("dp", c(sd, pp, gg, 0, n, yc), sum(seq_len(n) * mk), 1e-12)
  yn <- round(rnorm(n), 2); set.seed(sd); sel <- createDataPartition(yn, times = 1, p = pp, list = FALSE, groups = gg)[, 1]
  mk <- numeric(n); mk[sel] <- 1; add("dp", c(sd, pp, gg, 1, n, yn), sum(seq_len(n) * mk), 1e-12)
}
# preProcess: "pp" (mode, lo, hi, n, p, x column-major) mode 0 center 1 scale 2 center+scale 3 range; answered as sum(row * column * transformed value)
for (rep in 1:25) {
  n <- sample(6:40, 1); p <- sample(1:4, 1); X <- matrix(rnorm(n * p, rep(sample(-5:5, p), each = n), rep(runif(p, 0.5, 4), each = n)), n, p); d <- as.data.frame(X)
  lo <- runif(1, -2, 0); hi <- runif(1, 1, 3)
  for (mode in 0:3) {
    pr <- preProcess(d, method = switch(mode + 1, "center", "scale", c("center", "scale"), "range"), rangeBounds = c(lo, hi)); Y <- as.matrix(predict(pr, d))
    add("pp", c(mode, lo, hi, n, p, X), sum(outer(seq_len(n), seq_len(p), "*") * Y), 1e-10)
  }
}
# multi-class confusionMatrix: "cmk" (id, k, table column-major rows = prediction) id 0..6 overall, 7 + 11 * class + j the byClass columns
for (rep in 1:25) {
  k <- sample(3:5, 1); n <- sample(60:300, 1); ref <- sample(k, n, TRUE, prob = runif(k)); pr <- ifelse(runif(n) < 0.45, ref, sample(k, n, TRUE))
  tb <- table(Prediction = factor(pr, 1:k), Reference = factor(ref, 1:k)); if (any(tb == 0) || any(colSums(tb) == 0) || any(rowSums(tb) == 0)) next
  cm <- confusionMatrix(tb); ov <- as.numeric(cm$overall); bc <- as.numeric(t(cm$byClass))
  for (j in 1:7) add("cmk", c(j - 1, k, tb), ov[j], 1e-8)
  for (j in seq_along(bc)) add("cmk", c(7 + j - 1, k, tb), bc[j], 1e-8)
}
# BoxCoxTrans: "bc" (id, n, y[n]) id 0 lambda (-99 for NA) 1 sum(position * predicted)
for (rep in 1:30) {
  n <- sample(8:60, 1); y <- switch(rep %% 4 + 1, rexp(n, 1) + 0.1, exp(rnorm(n, 1, 0.7)), runif(n, 1, 5), rgamma(n, 2, 1) + 0.05); if (rep == 30) y[1] <- -1
  bt <- BoxCoxTrans(y); lam <- if (is.na(bt$lambda)) -99 else bt$lambda; add("bc", c(0, n, y), lam, 1e-12)
  add("bc", c(1, n, y), sum(seq_len(n) * predict(bt, y)), 1e-10)
}
emit("carets", "caret", list(cases))
