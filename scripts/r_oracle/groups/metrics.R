# yardstick and ModelMetrics performance metrics on vectors.
#   args: (n, truth[n], estimate[n], p1)  fn: numeric (truth, estimate): rmse mae mse rsq rsq_trad ccc huber(p1 = delta) mape smape mase
#   classification (truth 0/1, estimate a 0/1 prediction): accuracy kap fmeas(p1 = beta) mcc balacc jindex precision recall spec
#   probabilistic (truth 0/1, estimate a probability): auc gini logloss brier mm_ce mm_ppv mm_npv mm_kappa (p1 = cutoff)
suppressMessages({ library(yardstick); library(ModelMetrics) })
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261115)
fac <- function(v) factor(v, levels = c(1, 0))
for (rep in 1:8) {
  n <- c(20, 35, 50, 12, 80, 30, 60, 25)[rep]
  t <- round(runif(n, 1, 20), 2); e <- round(t + rnorm(n, 0, 2), 2)
  df <- data.frame(t = t, e = e); a <- c(n, t, e, 1)
  add("rmse", a, rmse_vec(t, e)); add("mae", a, mae_vec(t, e)); add("mse", a, ModelMetrics::mse(t, e))
  add("rsq", a, rsq_vec(t, e)); add("rsq_trad", a, rsq_trad_vec(t, e)); add("ccc", a, ccc_vec(t, e))
  for (d in c(1, 2.5)) add("huber", c(n, t, e, d), huber_loss_vec(t, e, delta = d))
  add("mape", a, mape_vec(t, e)); add("smape", a, smape_vec(t, e)); add("mase", a, mase_vec(t, e))
  y <- rbinom(n, 1, 0.45); pr <- round(runif(n), 3); pr[1] <- 0.5; pd <- as.numeric(pr > 0.5)
  if (length(unique(y)) < 2) next
  b <- c(n, y, pd, 1)
  add("accuracy", b, accuracy_vec(fac(y), fac(pd))); add("kap", b, kap_vec(fac(y), fac(pd)))
  for (be in c(1, 0.5)) add("fmeas", c(n, y, pd, be), f_meas_vec(fac(y), fac(pd), beta = be))
  add("mcc", b, mcc_vec(fac(y), fac(pd))); add("balacc", b, bal_accuracy_vec(fac(y), fac(pd))); add("jindex", b, j_index_vec(fac(y), fac(pd)))
  add("precision", b, precision_vec(fac(y), fac(pd))); add("recall", b, recall_vec(fac(y), fac(pd))); add("spec", b, spec_vec(fac(y), fac(pd)))
  for (cu in c(0.3, 0.5, 0.7)) {
    q <- c(n, y, pr, cu)
    add("auc", q, ModelMetrics::auc(y, pr)); add("gini", q, ModelMetrics::gini(y, pr)); add("logloss", q, ModelMetrics::logLoss(y, pr))
    add("brier", q, ModelMetrics::brier(y, pr)); add("mm_ce", q, ModelMetrics::ce(y, pd))
    add("mm_ppv", q, ModelMetrics::ppv(y, pr, cu)); add("mm_npv", q, ModelMetrics::npv(y, pr, cu)); add("mm_kappa", q, ModelMetrics::kappa(y, pr, cu))
  }
  add("roc_auc", c(n, y, pr, 1), roc_auc_vec(fac(y), pr))
}
#   iic: fn "iic" (n, t, e, 1); pr_auc, gain_capture, lift_curve on a 0/1 truth and a probability with ties: fn "prauc" "gaincap" (n, y, p, 0) "lift" (n, y, p, j) with j 0 length 1 sum
#   2 position-weighted sum; multiclass class metrics: fn "mc" (K, n, truth 0-based, est 0-based, which 0 precision 1 recall 2 spec 3 f_meas 4 bal_accuracy 5 j_index 6 kap 7 mcc 8 accuracy,
#   estimator 0 macro 1 micro 2 macro_weighted, beta); one-vs-all probabilities: fn "ova" (K, n, truth 0-based, probs row-major, which 0 pr_auc 1 gain_capture, estimator 0 or 2)
for (rep in 1:8) {
  n <- c(20, 35, 50, 12, 80, 30, 60, 25)[rep]
  t <- round(runif(n, 1, 20), 2); e <- round(t + rnorm(n, 0, 2), 2)
  add("iic", c(n, t, e, 1), iic_vec(t, e))
  y <- rbinom(n, 1, 0.45); pr <- round(runif(n), 1); if (length(unique(y)) < 2) next
  add("prauc", c(n, y, pr, 0), pr_auc_vec(fac(y), pr)); add("gaincap", c(n, y, pr, 0), gain_capture_vec(fac(y), pr))
  lf <- yardstick:::lift_curve_vec(fac(y), pr)$.lift[-1]; v <- as.numeric(lf); w <- seq_along(v)
  add("lift", c(n, y, pr, 0), length(v)); add("lift", c(n, y, pr, 1), sum(v)); add("lift", c(n, y, pr, 2), sum(w * v))
  K <- sample(3:4, 1); lv <- paste0("c", 1:K)
  tr <- sample(0:(K - 1), n, TRUE); es <- ifelse(runif(n) < 0.6, tr, sample(0:(K - 1), n, TRUE))
  if (length(unique(tr)) < K || length(unique(es)) < K) next
  tf <- factor(lv[tr + 1], levels = lv); ef <- factor(lv[es + 1], levels = lv)
  est <- c("macro", "micro", "macro_weighted")
  fns <- list(precision_vec, recall_vec, spec_vec, function(...) f_meas_vec(..., beta = 1), bal_accuracy_vec, j_index_vec)
  for (wh in 0:5) for (ei in 0:2) add("mc", c(K, n, tr, es, wh, ei, 1), fns[[wh + 1]](tf, ef, estimator = est[ei + 1]))
  for (ei in 0:2) add("mc", c(K, n, tr, es, 3, ei, 0.5), f_meas_vec(tf, ef, beta = 0.5, estimator = est[ei + 1]))
  add("mc", c(K, n, tr, es, 6, 0, 1), kap_vec(tf, ef)); add("mc", c(K, n, tr, es, 7, 0, 1), mcc_vec(tf, ef)); add("mc", c(K, n, tr, es, 8, 0, 1), accuracy_vec(tf, ef))
  P <- matrix(runif(n * K), n, K); P[cbind(seq_len(n), tr + 1)] <- P[cbind(seq_len(n), tr + 1)] + 0.5; P <- round(P / rowSums(P), 3)
  colnames(P) <- lv
  for (ei in c(0, 2)) {
    add("ova", c(K, n, tr, as.numeric(t(P)), 0, ei), pr_auc_vec(tf, P, estimator = est[ei + 1]))
    add("ova", c(K, n, tr, as.numeric(t(P)), 1, ei), gain_capture_vec(tf, P, estimator = est[ei + 1]))
    add("ova", c(K, n, tr, as.numeric(t(P)), 2, ei), roc_auc_vec(tf, P, estimator = est[ei + 1]))
  }
}
emit("metrics", c("yardstick", "ModelMetrics"), list(cases))
