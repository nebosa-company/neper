# EnvStats: rosnerTest, tolIntNormK, predIntNormK.
#   "ro" args (n, k, alpha, x[n], f, i): f 0 n.outliers 1 Mean.i 2 SD.i 3 Value 4 Obs.Num 5 R 6 lambda 7 Outlier (0 or 1), i = 0-based row
#   "tk" args (n, coverage, conf, kind): kind 0 content one-sided 1 content two-sided Wald-Wolfowitz 2 expectation one-sided 3 expectation two-sided
#   "pk" args (n, n.mean, k, two.sided, conf)
suppressMessages(library(EnvStats))
cases <- list()
set.seed(20261116)
for (rep in 1:40) {
  n <- sample(12:60, 1); x <- round(rnorm(n, 10, 2), 3)
  no <- sample(0:4, 1); if (no > 0) x[sample(n, no)] <- round(10 + sample(c(-1, 1), no, TRUE) * runif(no, 7, 14), 3)
  k <- sample(2:min(8, n - 2), 1); al <- c(0.05, 0.01, 0.1)[sample(3, 1)]
  r <- suppressWarnings(rosnerTest(x, k = k, alpha = al)); df <- r$all.stats
  add <- function(f, i, v) cases[[length(cases) + 1]] <<- case("ro", c(n, k, al, x, f, i), as.numeric(v), rel = 1e-9, abs = 1e-10)
  add(0, 0, r$n.outliers)
  for (i in 1:k) { add(1, i - 1, df$Mean.i[i]); add(2, i - 1, df$SD.i[i]); add(3, i - 1, df$Value[i]); add(4, i - 1, df$Obs.Num[i]); add(5, i - 1, df[i, "R.i+1"]); add(6, i - 1, df[i, "lambda.i+1"]); add(7, i - 1, df$Outlier[i]) }
}
for (rep in 1:60) {
  n <- sample(3:80, 1); cv <- c(0.9, 0.95, 0.99, 0.8)[sample(4, 1)]; cl <- c(0.9, 0.95, 0.99)[sample(3, 1)]
  for (kind in 0:3) {
    v <- switch(kind + 1,
      tolIntNormK(n, coverage = cv, conf.level = cl, ti.type = "upper"),
      tolIntNormK(n, coverage = cv, conf.level = cl, method = "wald.wolfowitz"),
      tolIntNormK(n, coverage = cv, cov.type = "expectation", ti.type = "upper"),
      tolIntNormK(n, coverage = cv, cov.type = "expectation"))
    cases[[length(cases) + 1]] <- case("tk", c(n, cv, cl, kind), as.numeric(v), rel = 1e-5, abs = 1e-7)
  }
}
for (rep in 1:60) {
  n <- sample(3:80, 1); nm <- sample(1:5, 1); k <- sample(c(1, 1, 2, 3, 5), 1); ts <- sample(0:1, 1); cl <- c(0.9, 0.95, 0.99)[sample(3, 1)]
  v <- predIntNormK(n, n.mean = nm, k = k, method = if (k == 1) "exact" else "Bonferroni", pi.type = if (ts == 1) "two-sided" else "upper", conf.level = cl)
  cases[[length(cases) + 1]] <- case("pk", c(n, nm, k, ts, cl), as.numeric(v), rel = 1e-9, abs = 1e-10)
}
emit("envstats", "EnvStats", list(cases))
