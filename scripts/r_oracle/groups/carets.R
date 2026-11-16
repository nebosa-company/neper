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
emit("carets", "caret", list(cases))
