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
# kendallTrendTest ("kt": (n, y, x, alt 0 two.sided 1 greater 2 less, correct, conf.level, field): 0 S 1 var.S 2 z 3 p 4 tau 5 slope 6 intercept 7 LCL 8 UCL 9 slopes count)
alts <- c("two.sided", "greater", "less")
for (rep in 1:60) {
  n <- sample(6:40, 1); x <- if (rep %% 3 == 0) sort(sample(1:(n %/% 2 + 2), n, TRUE)) else seq_len(n); y <- round(0.3 * x + rnorm(n, 0, 2), if (rep %% 2 == 0) 0 else 3)
  al <- sample(0:2, 1); cr <- rep %% 4 != 0; cl <- c(0.9, 0.95, 0.99)[sample(3, 1)]
  r <- tryCatch(suppressWarnings(kendallTrendTest(y, x, alternative = alts[al + 1], correct = cr, conf.level = cl)), error = function(e) NULL); if (is.null(r)) next
  out <- c(r$S, r$var.S, unname(r$statistic), r$p.value, unname(r$estimate["tau"]), unname(r$estimate["slope"]), unname(r$estimate["intercept"]), unname(r$interval$limits[1]), unname(r$interval$limits[2]), length(r$slopes))
  for (f in 0:9) cases[[length(cases) + 1]] <- case("kt", c(n, y, x, al, as.numeric(cr), cl, f), out[f + 1], rel = 1e-9, abs = 1e-10)
}
# kendallSeasonalTrendTest, independent observations ("kst": (n, y, season, year, alt, correct, conf.level, field): 0 chi-square 1 p 2 z 3 p 4 tau 5 slope 6 intercept 7 LCL 8 UCL 9 S 10 var.S 11 slopes count 12 seasons used)
for (rep in 1:50) {
  ny <- sample(4:12, 1); nse <- sample(2:6, 1); df <- expand.grid(year = seq_len(ny), season = seq_len(nse)); keep <- runif(nrow(df)) > 0.1; df <- df[keep, ]
  if (rep %% 3 == 0) df <- rbind(df, df[sample(nrow(df), 4), ])
  n <- nrow(df); y <- round(0.2 * df$year + rnorm(n, df$season, 1.5), if (rep %% 2 == 0) 0 else 2)
  al <- sample(0:2, 1); cr <- rep %% 4 != 0; cl <- c(0.9, 0.95, 0.99)[sample(3, 1)]
  r <- tryCatch(suppressWarnings(kendallSeasonalTrendTest(y, df$season, df$year, alternative = alts[al + 1], correct = cr, conf.level = cl)), error = function(e) NULL); if (is.null(r)) next
  out <- c(unname(r$statistic[1]), unname(r$p.value[1]), unname(r$statistic[2]), unname(r$p.value[2]), unname(r$estimate["tau"]), unname(r$estimate["slope"]), unname(r$estimate["intercept"]), unname(r$interval$limits[1]), unname(r$interval$limits[2]), sum(r$seasonal.S, na.rm = TRUE), sum(r$var.seasonal.S, na.rm = TRUE), r$interval$sample.size, as.numeric(r$parameters) + 1)
  for (f in 0:12) cases[[length(cases) + 1]] <- case("kst", c(n, y, df$season, df$year, al, as.numeric(cr), cl, f), out[f + 1], rel = 1e-9, abs = 1e-10)
}
# gofTest against the normal and lognormal distributions ("gof": (n, y, test, lnorm, alt, field): test 0 sw 1 sf 2 ad 3 cvm 4 lillie 5 skew 6 ppcc; field 0 statistic 1 p 2 z)
tn <- c("sw", "sf", "ad", "cvm", "lillie", "skew", "ppcc"); al2 <- c("two.sided", "less", "greater")
for (rep in 1:100) {
  n <- sample(c(9:40, 60, 120, 200), 1); ln <- rep %% 3 == 0; te <- (rep - 1) %% 7; al <- sample(0:2, 1)
  y <- if (rep %% 2 == 0) round(rnorm(n, 5, 2), 3) else round(rgamma(n, 3), 3) + 0.1; if (!ln) y <- y - 0 else y <- abs(y) + 0.05
  r <- tryCatch(suppressWarnings(if (te == 5) gofTest(y, test = tn[te + 1], distribution = if (ln) "lnorm" else "norm", alternative = al2[al + 1]) else gofTest(y, test = tn[te + 1], distribution = if (ln) "lnorm" else "norm")), error = function(e) NULL); if (is.null(r)) next
  out <- c(unname(r$statistic), r$p.value, if (is.null(r$z.value)) NaN else r$z.value)
  for (f in 0:2) if (!is.nan(out[f + 1])) cases[[length(cases) + 1]] <- case("gof", c(n, y, te, as.numeric(ln), al, f), out[f + 1], rel = if (te == 0 && f >= 1) 1e-5 else 1e-8, abs = 1e-10)
}
# tTestPower ("ttp": (n1, n2, delta.over.sigma, alpha, two.sample, alt, approx)) and tTestN ("ttn": (delta.over.sigma, alpha, power, two.sample, alt, approx)); alt 0 two.sided 1 less 2 greater
alts_t <- c("two.sided", "less", "greater")
for (rep in 1:80) {
  ts_ <- rep %% 2 == 0; al <- sample(0:2, 1); ap <- rep %% 5 == 0
  dos <- c(0.3, 0.5, 0.8, 1.2)[sample(4, 1)] * if (al == 1) -1 else sample(c(-1, 1), 1); if (al == 2) dos <- abs(dos)
  n1 <- sample(3:60, 1); n2 <- if (ts_) sample(3:60, 1) else n1; a <- c(0.01, 0.05, 0.1)[sample(3, 1)]
  v <- tryCatch(if (ts_) tTestPower(n1, n2, dos, a, "two.sample", alternative = alts_t[al + 1], approx = ap) else tTestPower(n1, delta.over.sigma = dos, alpha = a, sample.type = "one.sample", alternative = alts_t[al + 1], approx = ap), error = function(e) NA)
  if (is.finite(v)) cases[[length(cases) + 1]] <- case("ttp", c(n1, n2, dos, a, as.numeric(ts_), al, as.numeric(ap)), v, rel = 1e-7, abs = 1e-9)
  pw <- c(0.8, 0.9, 0.95)[sample(3, 1)]
  nn <- tryCatch(tTestN(dos, alpha = a, power = pw, sample.type = if (ts_) "two.sample" else "one.sample", alternative = alts_t[al + 1], approx = ap), error = function(e) NA)
  if (is.finite(nn)) cases[[length(cases) + 1]] <- case("ttn", c(dos, a, pw, as.numeric(ts_), al, as.numeric(ap)), nn, rel = 0, abs = 0)
}
# ciNormHalfWidth ("cihw": (n1, n2, sigma.hat, conf.level, two.sample)) and ciNormN ("cin": (half.width, sigma.hat, conf.level, two.sample))
for (rep in 1:80) {
  ts_ <- rep %% 2 == 0; n1 <- sample(3:80, 1); n2 <- if (ts_) sample(3:80, 1) else n1; sg <- c(0.5, 1, 2.5)[sample(3, 1)]; cl <- c(0.9, 0.95, 0.99)[sample(3, 1)]
  v <- if (ts_) ciNormHalfWidth(n1, n2, sigma.hat = sg, conf.level = cl, sample.type = "two.sample") else ciNormHalfWidth(n1, sigma.hat = sg, conf.level = cl, sample.type = "one.sample")
  cases[[length(cases) + 1]] <- case("cihw", c(n1, n2, sg, cl, as.numeric(ts_)), v, rel = 1e-9, abs = 1e-10)
  hw <- sg * c(0.1, 0.25, 0.5, 1)[sample(4, 1)]
  nn <- tryCatch(ciNormN(hw, sigma.hat = sg, conf.level = cl, sample.type = if (ts_) "two.sample" else "one.sample"), error = function(e) NA)
  if (is.finite(nn)) cases[[length(cases) + 1]] <- case("cin", c(hw, sg, cl, as.numeric(ts_)), nn, rel = 0, abs = 0)
}
emit("envstats", "EnvStats", list(cases))
