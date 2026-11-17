# imputeTS: na_ma and na_mean. NA is encoded as -999999 in the args.
#   args: (kind, k_or_option, n, series...)   fn "ma" (kind 0 simple, 1 linear, 2 exponential; k) -> the position-weighted sum of the result
#   fn "mean" (option 0 mean, 1 median, 2 mode, 3 geometric, 4 harmonic) -> the filled value; series is positive
suppressMessages(library(imputeTS))
cases <- list()
add <- function(fn, args, want, rel = 1e-9) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-12)
enc <- function(x) ifelse(is.na(x), -999999, x)
set.seed(20261205)
for (rep in 1:30) {
  n <- sample(12:30, 1); x <- round(runif(n, 1, 10), 1)
  if (rep %% 3 == 0) x[sample(n, 3)] <- round(x[1], 1)
  na <- sample(n, sample(2:6, 1)); if (rep %% 5 == 0) na <- c(na, 1, n)
  x[na] <- NA; if (sum(!is.na(x)) < 3) next
  w <- c("simple", "linear", "exponential")
  for (kind in 0:2) {
    k <- sample(1:5, 1)
    r <- na_ma(x, k = k, weighting = w[kind + 1])
    add("ma", c(kind, k, n, enc(x)), sum(r * seq_len(n)))
  }
  for (opt in 0:4) {
    r <- na_mean(x, option = c("mean", "median", "mode", "geometric", "harmonic")[opt + 1])
    add("mean", c(opt, 0, n, enc(x)), r[is.na(x)][1])
  }
}
# na_locf "locf" (option 0..2 remaining, +10 for nocb; index; n; series) and na_interpolation "interp" (0 linear 1 spline; index; n; series), each answered per position
for (rep in 1:30) {
  n <- sample(12:30, 1); x <- round(runif(n, 1, 10), 1); na <- sample(n, sample(2:6, 1)); if (rep %% 3 == 0) na <- c(na, 1); if (rep %% 4 == 0) na <- c(na, n)
  x[na] <- NA; if (sum(!is.na(x)) < 4) next
  for (nc in c(FALSE, TRUE)) for (rm in 0:2) { r <- suppressWarnings(na_locf(x, option = if (nc) "nocb" else "locf", na_remaining = c("rev", "keep", "mean")[rm + 1])); for (k in seq_len(n)) add("locf", c(rm + if (nc) 10 else 0, k - 1, n, enc(x)), r[k]) }
  for (op in 0:2) { r <- suppressWarnings(na_interpolation(x, option = c("linear", "spline", "stine")[op + 1])); for (k in seq_len(n)) add("interp", c(op, k - 1, n, enc(x)), r[k]) }
}
# maxgap with na_locf (0 locf, 1 nocb, na_remaining keep) and na_interpolation (2 linear, 3 spline): "maxgap" (option, index, n, series..., maxgap)
for (rep in 1:30) {
  n <- sample(14:30, 1); x <- round(runif(n, 1, 10), 1); na <- c(sample(n, sample(3:7, 1))); x[na] <- NA; x[c(3, 4, 5, 6)] <- NA; if (sum(!is.na(x)) < 4) next; mg <- sample(1:3, 1)
  for (op in 0:3) { r <- suppressWarnings(switch(op + 1, na_locf(x, "locf", "keep", maxgap = mg), na_locf(x, "nocb", "keep", maxgap = mg), na_interpolation(x, "linear", maxgap = mg), na_interpolation(x, "spline", maxgap = mg)))
    for (k in seq_len(n)) add("maxgap", c(op, k - 1, n, enc(x), mg), r[k]) }
}
# na_random "rnd" (seed, index, n, series..., lower or -999999, upper or -999999) and na_replace "repl" (0, index, n, series..., fill)
for (rep in 1:20) {
  n <- sample(12:30, 1); x <- round(runif(n, 1, 10), 1); na <- sample(n, sample(2:6, 1)); x[na] <- NA; sd <- sample(1:100000, 1)
  lo <- if (rep %% 2) NULL else 0.5; hi <- if (rep %% 2) NULL else 12
  set.seed(sd); r <- na_random(x, lower_bound = lo, upper_bound = hi); fl <- sample(c(0, -1, 7.5), 1); r2 <- na_replace(x, fill = fl)
  for (k in seq_len(n)) { add("rnd", c(sd, k - 1, n, enc(x), if (is.null(lo)) -999999 else lo, if (is.null(hi)) -999999 else hi), r[k]); add("repl", c(0, k - 1, n, enc(x), fl), r2[k]) }
}
# na_seadec "sea" (algorithm 0 interpolation 1 locf 2 mean, index, n, series..., period)
for (rep in 1:20) {
  per <- sample(4:8, 1); n <- per * sample(4:6, 1); tt <- seq_len(n); x <- round(10 + 0.1 * tt + 2 * sin(2 * pi * tt / per) + rnorm(n, 0, 0.3), 2)
  na <- sample(seq(2, n - 1), sample(2:5, 1)); x[na] <- NA; alg <- (rep - 1) %% 3
  r <- suppressWarnings(na_seadec(ts(x, frequency = per), algorithm = c("interpolation", "locf", "mean")[alg + 1]))
  for (k in seq_len(n)) add("sea", c(alg, k - 1, n, enc(x), per), as.numeric(r[k]))
}
# na_seasplit "split" (algorithm, index, n, series..., period): every cycle position keeps at least three observed values
for (rep in 1:20) {
  per <- sample(3:6, 1); n <- per * sample(5:7, 1); tt <- seq_len(n); x <- round(10 + 0.1 * tt + 2 * sin(2 * pi * tt / per) + rnorm(n, 0, 0.3), 2)
  na <- sample(n, sample(2:5, 1)); x[na] <- NA; alg <- (rep - 1) %% 3
  ok <- all(sapply(seq_len(per), function(i) sum(!is.na(x[seq(i, n, by = per)])) >= 3)); if (!ok) next
  r <- suppressWarnings(na_seasplit(ts(x, frequency = per), algorithm = c("interpolation", "locf", "mean")[alg + 1]))
  for (k in seq_len(n)) add("split", c(alg, k - 1, n, enc(x), per), as.numeric(r[k]))
}
# statsNA "stats" (which 0 length 1 number of NAs 2 gaps 3 average gap 4 percentage 5 longest 6 most frequent 7 most weighty, 0, n, series...)
for (rep in 1:30) {
  n <- sample(10:40, 1); x <- round(runif(n, 1, 10), 1); na <- sample(n, sample(2:min(12, n - 1), 1)); x[na] <- NA; if (rep %% 4 == 0) x[n] <- NA
  st <- statsNA(x, print_only = FALSE); v <- c(st$length_series, st$number_NAs, st$number_na_gaps, st$average_size_na_gaps, as.numeric(sub("%", "", st$percentage_NAs)) , st$longest_na_gap, st$most_frequent_na_gap, st$most_weighty_na_gap)
  for (w in 0:7) if (w != 4) add("stats", c(w, 0, n, enc(x)), v[w + 1])
}
# na_kalman with a user state-space model "kal" (smooth 1 or 0, index, n, series..., p, nit, h, T, Z, V, a, P, Pn; matrices row-major)
encmod <- function(mod, nit) c(length(mod$a), nit, mod$h, as.vector(t(mod$T)), mod$Z, as.vector(t(mod$V)), mod$a, as.vector(t(mod$P)), as.vector(t(mod$Pn)))
for (rep in 1:40) {
  p <- sample(1:3, 1); n <- sample(12:30, 1)
  Tm <- matrix(round(runif(p * p, -0.7, 0.7), 2), p, p); if (p > 1) Tm <- Tm + diag(0.3, p)
  Lm <- matrix(round(runif(p * p, -1, 1), 2), p, p); Vm <- Lm %*% t(Lm) + diag(0.05, p)
  P0 <- crossprod(matrix(round(runif(p * p, -1, 1), 2), p, p)) + diag(0.2, p); Pn0 <- P0 * 1.5
  mod <- list(T = Tm, Z = round(runif(p, 0.3, 1.5), 2), h = round(runif(1, 0.1, 1), 2), V = Vm, a = round(runif(p, -1, 1), 2), P = P0, Pn = Pn0)
  x <- round(cumsum(rnorm(n)) + 5, 2); na <- sample(n, sample(2:6, 1)); if (rep %% 4 == 0) na <- c(na, 1, n); x[na] <- NA
  nit <- c(-1, 0, 2)[rep %% 3 + 1]
  for (sm in c(TRUE, FALSE)) {
    r <- tryCatch(na_kalman(x, model = mod, smooth = sm, nit = nit), error = function(e) NULL)
    if (is.null(r)) next
    for (k in seq_len(n)) add("kal", c(as.numeric(sm), k - 1, n, enc(x), encmod(mod, nit)), r[k])
  }
}
# na_kalman with model = "StructTS" "sts" (smooth 1 or 0, index, n, series..., type 0 level 1 trend 2 BSM, frequency); a plain vector is a trend model, a ts of frequency > 1 a BSM
for (rep in 1:45) {
  kind <- (rep - 1) %% 3; nf <- if (kind == 2) sample(3:6, 1) else 1; n <- if (kind == 2) nf * sample(4:6, 1) else sample(15:40, 1)
  tt <- seq_len(n); x <- round(10 + cumsum(rnorm(n, 0, 0.4)) + (if (kind == 1) 0.1 * tt else 0) + (if (kind == 2) 1.5 * sin(2 * pi * tt / nf) else 0) + rnorm(n, 0, 0.3), 2)
  na <- sample(seq(2, n), sample(2:5, 1)); if (rep %% 7 == 0) na <- c(na, 1); x[na] <- NA
  if (sum(!is.na(x)) < 5) next
  for (sm in c(TRUE, FALSE)) {
    xin <- if (kind == 2) ts(x, frequency = nf) else x
    r <- tryCatch(suppressWarnings(na_kalman(xin, model = "StructTS", smooth = sm, type = c("level", "trend", "BSM")[kind + 1])), error = function(e) NULL)
    if (is.null(r)) next
    r <- as.numeric(r)
    for (k in seq_len(n)) add("sts", c(as.numeric(sm), k - 1, n, enc(x), kind, nf), r[k], rel = 1e-6)
  }
}
# stats::arima "arima" (p, d, q, kind 0 none 1 intercept 2 drift, method 0 CSS-ML 1 ML 2 CSS, quantity, n, series...): quantity 0 aic, 1 loglik, 2 sigma2, 10+i coef i, 30+i model a[i], 50+i diag P[i]
for (rep in 1:60) {
  p <- sample(0:2, 1); d <- sample(0:1, 1); q <- sample(0:2, 1); n <- sample(25:60, 1)
  ar <- if (p) c(0.5, -0.2)[1:p] else NULL; ma <- if (q) c(0.4, 0.2)[1:q] else NULL
  x <- round(arima.sim(list(order = c(p, 0, q), ar = ar, ma = ma), n) + 5, 3); if (d == 1) x <- round(cumsum(x - 5) + 5, 3)
  kind <- if (d == 0) sample(0:1, 1) else sample(c(0, 2), 1)
  method <- (rep - 1) %% 3
  if (rep %% 2 == 0) { x[sample(2:n, 3)] <- NA; method <- 1 }
  if (rep %% 10 == 0) x[1:2] <- NA
  xr <- if (kind == 2) seq_along(x) else NULL
  fit <- tryCatch(suppressWarnings(stats::arima(x, order = c(p, d, q), include.mean = (kind == 1), xreg = xr, method = c("CSS-ML", "ML", "CSS")[method + 1])), error = function(e) NULL)
  if (is.null(fit)) next
  if (rep %% 10 == 0) next
  vals <- list(`0` = fit$aic, `1` = fit$loglik, `2` = fit$sigma2)
  for (i in seq_along(fit$coef)) vals[[as.character(10 + i - 1)]] <- unname(fit$coef[i])
  for (i in seq_along(fit$model$a)) { vals[[as.character(30 + i - 1)]] <- fit$model$a[i]; vals[[as.character(50 + i - 1)]] <- fit$model$P[i, i] }
  for (nm in names(vals)) if (!is.na(vals[[nm]])) add("arima", c(p, d, q, kind, method, as.numeric(nm), n, enc(x)), vals[[nm]], rel = if (as.numeric(nm) <= 2) 1e-6 else 1e-4)
}
# na_kalman with model = "auto.arima" "aa" (smooth 1 or 0, 0, n, series...) -> the position-weighted sum of the result
suppressMessages(library(forecast))
for (rep in 1:40) {
  n <- if (rep %% 20 == 0) 170 else sample(15:60, 1); kind <- rep %% 4
  e <- arima.sim(list(ar = if (kind == 0) 0.6 else NULL, ma = if (kind == 1) 0.5 else NULL), n)
  x <- round(switch(kind + 1, 10 + e, 10 + e, 10 + cumsum(rnorm(n, 0.2, 0.5)), 5 + 0.05 * seq_len(n) + e), 3)
  na <- sample(seq(2, n - 1), sample(2:min(8, n %/% 5), 1)); if (rep %% 7 == 0) na <- c(na, 1, 2); if (rep %% 9 == 0) na <- c(na, n)
  x[na] <- NA
  for (sm in c(TRUE, FALSE)) {
    r <- tryCatch(suppressWarnings(na_kalman(x, model = "auto.arima", smooth = sm)), error = function(e) NULL)
    if (is.null(r)) next
    add("aa", c(as.numeric(sm), 0, n, enc(x)), sum(r * seq_len(n)), rel = 1e-6)
  }
}
emit("imputets", "imputeTS", list(cases))
