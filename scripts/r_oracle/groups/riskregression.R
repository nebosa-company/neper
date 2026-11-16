# riskRegression Score(): IPCW Brier score and AUC of a predicted risk at one horizon (Kaplan-Meier censoring weights, no ties).
#   args: (n, horizon, time[n], event[n], risk[n])
#   fn "brier" "auc"
suppressMessages({library(riskRegression); library(survival)})
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-10)
set.seed(20270104)
for (rep in 1:24) {
  n <- sample(50:200, 1); x <- rnorm(n); tt <- rexp(n, exp(0.5 * x)); cc <- runif(n, 0, quantile(tt, 0.85)); y <- pmin(tt, cc); ev <- as.numeric(tt <= cc)
  risk <- plogis(x + rnorm(n, 0, 0.5)); hor <- as.numeric(quantile(y, runif(1, 0.3, 0.7)))
  d <- data.frame(y, ev, x)
  s <- tryCatch(Score(list(m = risk), formula = Surv(y, ev) ~ 1, data = d, times = hor, metrics = c("auc", "brier"), null.model = FALSE, se.fit = FALSE, conf.int = FALSE), error = function(e) NULL)
  if (is.null(s)) next
  a <- c(n, hor, y, ev, risk)
  add("brier", a, s$Brier$score$Brier); add("auc", a, s$AUC$score$AUC)
}
emit("riskregression", "riskRegression", list(cases))
