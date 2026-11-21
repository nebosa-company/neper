# TSA: the periodogram.
#   args: (n, y...)   fn "pgram": the sum of spec_j * j over the frequencies j / n
suppressMessages(library(TSA))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261221)
for (rep in 1:20) {
  n <- sample(8:60, 1); y <- round(cumsum(rnorm(n)) + sin(seq_len(n)), 4)
  p <- periodogram(ts(y), plot = FALSE)
  add("pgram", c(n, y), sum(p$spec * seq_along(p$spec)))
}
for (rep in 1:14) {
  n <- sample(30:120, 1); y <- round(rnorm(n) * (1 + 0.8 * (rep %% 2) * abs(sin(seq_len(n) / 5))), 4)
  gl <- sample(4:15, 1)
  ml <- McLeod.Li.test(y = y, gof.lag = gl, plot = FALSE)$p.values
  add("mcl", c(n, gl, y), sum(ml * seq_along(ml)))
}
# eacf: "eacf" (n, ar.max, ma.max, index row-major, z[n]); index = row * (ma.max + 1) + column
for (rep in 1:6) {
  n <- sample(80:110, 1); arm <- sample(3:6, 1); mam <- sample(4:9, 1); z <- as.numeric(arima.sim(list(ar = 0.5, ma = 0.3), n)); e <- suppressWarnings(eacf(z, ar.max = arm, ma.max = mam))$eacf
  for (r in 0:arm) for (cc in 0:mam) add("eacf", c(n, arm, mam, r * (mam + 1) + cc, z), e[r + 1, cc + 1])
}
# Box.test Ljung-Box p-values (tsdiag): "bl" args (n, gof, fitdf, x[n]); the p-values at lags fitdf + 1 .. gof weighted by lag
set.seed(20262499)
for (rep in 1:30) {
  n <- sample(60:300, 1); gl <- sample(8:20, 1); fd <- sample(0:3, 1)
  x <- if (rep %% 2 == 0) as.numeric(arima.sim(list(ar = runif(1, 0.1, 0.7)), n)) else rnorm(n)
  pv <- sapply((fd + 1):gl, function(i) Box.test(x, lag = i, type = "Ljung-Box", fitdf = fd)$p.value)
  cases[[length(cases) + 1]] <- case("bl", c(n, gl, fd, x), sum(pv * ((fd + 1):gl)), rel = 1e-9, abs = 1e-12)
}
# stats::ar.ols for one series: "aro" args (n, x[n], aic, order.max (0 the default), demean, intercept, which, idx) with which 0 order, 1 var.pred, 2 x.mean, 3 x.intercept, 4 ar[idx + 1], 5 resid[idx + 1] (idx past the NA)
for (rep in 1:20) {
  n <- sample(40:200, 1); x <- as.numeric(arima.sim(list(ar = c(0.5, -0.3)[seq_len(1 + rep %% 2)]), n)) + (rep %% 3) * 2; x <- round(x, 4)
  aic <- rep %% 4 != 0; om <- c(0, 5, 8, 0)[1 + rep %% 4]; dm <- rep %% 5 != 0
  r <- tryCatch(suppressWarnings(ar.ols(x, aic = aic, order.max = if (om > 0) om else NULL, demean = dm, intercept = dm)), error = function(e) NULL); if (is.null(r)) next
  a <- c(n, x, aic, om, dm, dm)
  cases[[length(cases) + 1]] <- case("aro", c(a, 0, 0), r$order, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("aro", c(a, 1, 0), r$var.pred, rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("aro", c(a, 2, 0), r$x.mean, rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("aro", c(a, 3, 0), if (is.null(r$x.intercept)) 0 else r$x.intercept, rel = 1e-9, abs = 1e-12)
  for (k in seq_len(r$order)) cases[[length(cases) + 1]] <- case("aro", c(a, 4, k - 1), as.numeric(r$ar)[k], rel = 1e-8, abs = 1e-10)
  for (k in sample(seq(r$order + 1, n), 3)) cases[[length(cases) + 1]] <- case("aro", c(a, 5, k - 1), as.numeric(r$resid)[k], rel = 1e-8, abs = 1e-10)
}
# TSA::armasubsets + summary.armasubsets: "asub" args (n, nar, nma, y[n], k, q); k the subset size 1 .. min(8, columns), q 0 mask over the columns (lags of y then lags of the AR residuals) 1 rss 2 rsq 3 adjR2 4 Cp 5 BIC
set.seed(20262611)
for (rep in 1:12) {
  n <- sample(50:80, 1); nar <- sample(c(1, 2, 3, 4, 5, 6), 1); nma <- sample(2:6, 1)
  y <- round(as.numeric(arima.sim(list(ar = c(0.6, -0.3), ma = 0.4), n)) + 0.5 * (rep %% 2), 4)
  r <- tryCatch(suppressWarnings(armasubsets(y = ts(y), nar = nar, nma = nma, y.name = "y")), error = function(e) NULL); if (is.null(r)) next
  s <- summary(r); cols <- ncol(s$which) - 1; kk <- nrow(s$which)
  # the design armasubsets regresses on, to tell a unique best subset from a tie (columns that are linearly dependent give subsets of equal rss, decided by rounding noise)
  res <- ar(y, method = "ols")$resid; xd <- NULL
  if (nar > 1) for (i in 1:nar) xd <- cbind(xd, zlag(y, d = i))
  if (nma > 1) for (j in 1:nma) xd <- cbind(xd, zlag(res, d = j))
  xd <- na.omit(cbind(y, xd)); yd <- xd[, 1]; xd <- xd[, -1, drop = FALSE]
  rssof <- function(cs) sum(lm.fit(cbind(1, xd[, cs, drop = FALSE]), yd)$residuals^2)
  for (k in seq_len(kk)) {
    rs <- apply(combn(cols, k), 2, rssof); unique_best <- length(rs) == 1 || sort(rs)[2] > min(rs) * (1 + 1e-8)
    for (q in 1:6) if (q > 1 || unique_best) cases[[length(cases) + 1]] <- case("asub", c(n, nar, nma, y, k, q - 1), c(sum(2^(which(s$which[k, -1]) - 1)), s$rss[k], s$rsq[k], s$adjR2[k], s$Cp[k], s$BIC[k])[q], rel = if (q == 1) 0 else 1e-8, abs = if (q == 1) 0 else 1e-9)
  }
}
emit("tsa", "TSA", list(cases))
