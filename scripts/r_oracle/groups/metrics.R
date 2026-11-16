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
emit("metrics", c("yardstick", "ModelMetrics"), list(cases))
