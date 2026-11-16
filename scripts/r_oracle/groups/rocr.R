# ROCR: performance measures over all cutoffs.
#   args: (kind, n, pred[n]..., labels[n]...)   fn "meas": the sum of the finite values of measure `kind` over the cutoffs weighted by position (1-based), and "cnt": the finite count
#   kind: 0 acc 1 err 2 fpr 3 tpr 4 fnr 5 tnr 6 prec 7 f 8 lift 9 mat 10 sens 11 spec 12 npv 13 ppv; kind 99 is the trapezoid AUC
suppressMessages(library(ROCR))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-10)
meas <- c("acc", "err", "fpr", "tpr", "fnr", "tnr", "prec", "f", "lift", "mat", "sens", "spec", "npv", "ppv")
set.seed(20261217)
for (rep in 1:12) {
  n <- sample(15:60, 1); lab <- rbinom(n, 1, 0.45); if (sum(lab) < 2 || sum(lab) > n - 2) next
  pred <- round(rnorm(n) + 0.9 * lab, if (rep %% 3 == 0) 1 else 3)
  p <- prediction(pred, lab)
  for (kd in 0:13) {
    v <- performance(p, meas[kd + 1])@y.values[[1]]
    ok <- is.finite(v)
    add("meas", c(kd, n, pred, lab), sum(v[ok] * seq_along(v)[ok]))
    add("cnt", c(kd, n, pred, lab), sum(ok))
  }
  add("meas", c(99, n, pred, lab), performance(p, "auc")@y.values[[1]])
}
# more measures: kinds 14 rpp, 15 phi, 16 cost (cost.fp = cost.fn = 1) through "meas"/"cnt" as above; "mxe" and "rmse" on predictions in (0, 1): args (kind, n, pred, labels)
meas2 <- c("rpp", "phi", "cost")
for (rep in 1:10) {
  n <- sample(15:60, 1); lab <- rbinom(n, 1, 0.45); if (sum(lab) < 2 || sum(lab) > n - 2) next
  pred <- round(plogis(rnorm(n) + 0.9 * lab), if (rep %% 3 == 0) 2 else 4); p <- prediction(pred, lab)
  for (kd in 14:16) { v <- performance(p, meas2[kd - 13])@y.values[[1]]; ok <- is.finite(v); add("meas", c(kd, n, pred, lab), sum(v[ok] * seq_along(v)[ok])); add("cnt", c(kd, n, pred, lab), sum(ok)) }
  if (all(pred > 0 & pred < 1)) { add("mxe", c(90, n, pred, lab), performance(p, "mxe")@y.values[[1]]); add("rmse", c(91, n, pred, lab), performance(p, "rmse")@y.values[[1]]) }
}
emit("rocr", "ROCR", list(cases))
