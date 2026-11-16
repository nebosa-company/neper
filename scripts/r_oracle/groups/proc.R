# pROC: auc, DeLong variance and interval, and the paired DeLong test.
#   args: (n, y[n]..., x1[n]..., x2[n]...)   fn "auc" "var" "cilo" "cihi" (of x1), "z" "p" (roc.test of x1 against x2)
suppressMessages(library(pROC))
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261216)
for (rep in 1:20) {
  n <- sample(20:80, 1); y <- rbinom(n, 1, 0.4); if (sum(y) < 3 || sum(y) > n - 3) next
  s <- c(0.8, 1.5, -0.7, 0.3)[rep %% 4 + 1]
  x1 <- round(rnorm(n) + s * y, if (rep %% 3 == 0) 1 else 4); x2 <- round(rnorm(n) + 0.4 * y + 0.3 * x1, if (rep %% 3 == 0) 1 else 4)
  r1 <- roc(y, x1, quiet = TRUE); r2 <- roc(y, x2, quiet = TRUE)
  a <- c(n, y, x1, x2)
  add("auc", a, as.numeric(auc(r1))); add("var", a, var(r1))
  ci <- ci.auc(r1); add("cilo", a, ci[1]); add("cihi", a, ci[3])
  rt <- roc.test(r1, r2, method = "delong", paired = TRUE)
  add("z", a, as.numeric(rt$statistic)); add("p", a, rt$p.value)
}
# coords: ("ncoord" "ssens" "sspec" "sthr") args (n, y, x1, x2) with r1 = roc(y, x1) at every threshold; ("atsens" "atspec") args (n, y, x1, x2, t) at the threshold t = a data midpoint
for (rep in 1:20) {
  n <- sample(20:80, 1); y <- rbinom(n, 1, 0.4); if (sum(y) < 3 || sum(y) > n - 3) next
  s <- c(0.8, 1.5, -0.7, 0.3)[rep %% 4 + 1]; x1 <- round(rnorm(n) + s * y, if (rep %% 3 == 0) 1 else 4); r1 <- roc(y, x1, quiet = TRUE)
  cc <- coords(r1, "all", ret = c("threshold", "sensitivity", "specificity"), transpose = FALSE); a <- c(n, y, x1, x1)
  add("ncoord", a, nrow(cc)); add("ssens", a, sum(cc$sensitivity)); add("sspec", a, sum(cc$specificity)); add("sthr", a, sum(cc$threshold[is.finite(cc$threshold)]))
  ux <- sort(unique(x1)); for (t in sample((ux[-1] + ux[-length(ux)]) / 2, 3)) { ct <- coords(r1, t, "threshold", ret = c("sensitivity", "specificity"), transpose = FALSE); add("atsens", c(a, t), ct$sensitivity); add("atspec", c(a, t), ct$specificity) }
}
# coords best: ("bcnt" "bthr" "bcrit") args (n, y, x1, x2, method 0 youden 1 closest.topleft, cost, prev)
for (rep in 1:20) {
  n <- sample(20:80, 1); y <- rbinom(n, 1, 0.4); if (sum(y) < 3 || sum(y) > n - 3) next
  s <- c(0.8, 1.5, -0.7, 0.3)[rep %% 4 + 1]; x1 <- round(rnorm(n) + s * y, if (rep %% 3 == 0) 1 else 4); r1 <- roc(y, x1, quiet = TRUE)
  for (m in 0:1) { cost <- if (rep %% 2 == 0) 1 else round(runif(1, 0.5, 2), 2); prev <- if (rep %% 2 == 0) 0.5 else round(runif(1, 0.2, 0.8), 2)
    cb <- coords(r1, "best", ret = c("threshold", "sensitivity", "specificity"), best.method = c("youden", "closest.topleft")[m + 1], best.weights = c(cost, prev), transpose = FALSE)
    a <- c(n, y, x1, x1, m, cost, prev); add("bcnt", a, nrow(cb)); add("bthr", a, cb$threshold[1]); r <- (1 - prev) / (cost * prev)
    add("bcrit", a, if (m == 0) max(cb$sensitivity + r * cb$specificity) else max(-((1 - cb$sensitivity)^2 + r * (1 - cb$specificity)^2))) }
}
# partial auc: ("pauc") args (n, y, x1, x2, hi, lo, focus 0 specificity 1 sensitivity, correct)
for (rep in 1:30) {
  n <- sample(20:80, 1); y <- rbinom(n, 1, 0.4); if (sum(y) < 3 || sum(y) > n - 3) next
  s <- c(0.8, 1.5, -0.7, 0.3)[rep %% 4 + 1]; x1 <- round(rnorm(n) + s * y, if (rep %% 3 == 0) 1 else 4); r1 <- roc(y, x1, quiet = TRUE)
  for (it in 1:4) { hi <- sample(c(1, 0.95, 0.9, 0.85), 1); lo <- sample(c(0.8, 0.75, 0.6, 0.5, 0.7), 1); foc <- sample(0:1, 1); cor <- sample(0:1, 1)
    v <- suppressWarnings(tryCatch(as.numeric(auc(r1, partial.auc = c(hi, lo), partial.auc.focus = c("specificity", "sensitivity")[foc + 1], partial.auc.correct = cor == 1)), error = function(e) NA))
    add("pauc", c(n, y, x1, x1, hi, lo, foc, cor), v) }
}
# multiclass.roc: ("mcauc") args (k, n, class codes 0..k-1 [n], x[n]) -> the multiclass AUC
for (rep in 1:30) {
  k <- sample(3:5, 1); n <- sample(30:100, 1); cl <- sample(0:(k - 1), n, TRUE); if (length(unique(cl)) < k) next
  x <- round(rnorm(n) + 0.7 * cl * sample(c(1, -1), 1), if (rep %% 3 == 0) 1 else 4)
  r <- tryCatch(suppressWarnings(multiclass.roc(cl, x, quiet = TRUE)), error = function(e) NULL); if (is.null(r)) next
  cases[[length(cases) + 1]] <- case("mcauc", c(k, n, cl, x), as.numeric(r$auc), rel = 1e-9, abs = 1e-12)
}
# roc.test unpaired delong: ("du_z" "du_p") args (n1, n2, y1[n1], x1[n1], y2[n2], x2[n2])
for (rep in 1:25) {
  n1 <- sample(20:70, 1); n2 <- sample(20:70, 1); y1 <- rbinom(n1, 1, 0.4); y2 <- rbinom(n2, 1, 0.5); if (sum(y1) < 3 || sum(y1) > n1 - 3 || sum(y2) < 3 || sum(y2) > n2 - 3) next
  x1 <- round(rnorm(n1) + 0.9 * y1, 3); x2 <- round(rnorm(n2) + 0.5 * y2, 3)
  rt <- suppressWarnings(roc.test(roc(y1, x1, quiet = TRUE), roc(y2, x2, quiet = TRUE), method = "delong", paired = FALSE))
  a <- c(n1, n2, y1, x1, y2, x2)
  cases[[length(cases) + 1]] <- case("du_z", a, as.numeric(rt$statistic), rel = 1e-9, abs = 1e-12); cases[[length(cases) + 1]] <- case("du_p", a, rt$p.value, rel = 1e-9, abs = 1e-12)
}
emit("proc", "pROC", list(cases))
