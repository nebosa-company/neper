# pastecs: turnpoints (counts, positions, probabilities, information) and stat.desc (basic, desc, norm without Shapiro).
#   args: (kind, p, n, x[n])  kind 0 turnpoints   1 stat.desc (p = confidence level)
#   fn "nturns" "firstpeak" "npeaks" "npits" "tppos_s" "tppos_w" "proba_s" "proba_w" "info_s" "info_w"; "d_<name>" for stat.desc
suppressMessages(library(pastecs))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261116)
for (rep in 1:40) {
  n <- sample(6:80, 1); x <- if (rep %% 2 == 0) round(rnorm(n), 1) else cumsum(rnorm(n))
  a <- c(0, 0, n, x)
  t <- suppressWarnings(turnpoints(x))
  if (is.na(t$nturns)) next
  add("nturns", a, t$nturns); add("firstpeak", a, as.numeric(t$firstispeak)); add("npeaks", a, sum(t$peaks)); add("npits", a, sum(t$pits))
  add("tppos_s", a, sum(t$tppos)); add("tppos_w", a, sum(seq_along(t$tppos) * t$tppos))
  add("proba_s", a, sum(t$proba)); add("proba_w", a, sum(seq_along(t$proba) * t$proba)); add("info_s", a, sum(t$info)); add("info_w", a, sum(seq_along(t$info) * t$info))
  pl <- c(0.9, 0.95, 0.99)[rep %% 3 + 1]; y <- round(rnorm(n, 3, 2), 2); b <- c(1, pl, n, y)
  s <- stat.desc(y, basic = TRUE, desc = TRUE, norm = TRUE, p = pl)
  nm <- c(nbr.null = "nbr.null", min = "min", max = "max", range = "range", sum = "sum", median = "median", mean = "mean", SE.mean = "SE.mean", CI.mean = "CI.mean", var = "var", std.dev = "std.dev", coef.var = "coef.var", skewness = "skewness", skew.2SE = "skew.2SE", kurtosis = "kurtosis", kurt.2SE = "kurt.2SE")
  for (k in names(nm)) add(paste0("d_", k), b, unname(if (k == "CI.mean") s[startsWith(names(s), "CI.mean")][1] else s[[nm[[k]]]]))
  add("d_normtest.W", b, s[["normtest.W"]]); add("d_normtest.p", b, s[["normtest.p"]])
}
# decdiff (kind 2: args (2, 0, n, x, type, lag, order, ends, which, idx)) and decmedian (kind 3: (3, 0, n, x, type, order, times, ends, which, idx)); fn "dec"; ends 0 NAs 1 fill 2 drop (median has only 0 and 1); which 0 filtered 1 residuals; NA values are not emitted
for (rep in 1:40) {
  n <- sample(15:60, 1); x <- round(cumsum(rnorm(n)) + 10, 2); ty <- rep %% 2
  tn <- c("additive", "multiplicative")[ty + 1]
  lag <- sample(1:3, 1); ord <- sample(1:2, 1); en <- sample(0:2, 1)
  r <- decdiff(ts(x), type = tn, lag = lag, order = ord, ends = c("NAs", "fill", "drop")[en + 1])
  for (w in 0:1) { v <- as.vector(r$series[, w + 1]); for (i in seq_along(v)) if (is.finite(v[i])) cases[[length(cases) + 1]] <- case("dec", c(2, 0, n, x, ty, lag, ord, en, w, i - 1), v[i], rel = 1e-9, abs = 1e-10) }
  ord2 <- sample(1:3, 1); tm <- sample(1:3, 1); en2 <- sample(0:1, 1)
  r <- decmedian(ts(x), type = tn, order = ord2, times = tm, ends = c("NAs", "fill")[en2 + 1])
  for (w in 0:1) { v <- as.vector(r$series[, w + 1]); for (i in seq_along(v)) if (is.finite(v[i])) cases[[length(cases) + 1]] <- case("dec", c(3, 0, n, x, ty, ord2, tm, en2, w, i - 1), v[i], rel = 1e-9, abs = 1e-10) }
}
# decaverage (kind 4: args (4, 0, n, x, type, times, sides, ends, which, idx, freq, nw, weights[nw])); weights are given explicitly (the periodic and numeric-order forms are expanded here as the package does); ends 0 NAs 1 fill 2 circular 3 periodic
for (rep in 1:60) {
  f <- sample(c(4, 7, 12), 1); n <- sample((2 * f):(5 * f), 1); x <- round(cumsum(rnorm(n)) + 10 + 2 * sin(2 * pi * (1:n) / f), 2); ty <- rep %% 2
  tn <- c("additive", "multiplicative")[ty + 1]; tm <- sample(1:2, 1); sd <- sample(1:2, 1); en <- sample(0:3, 1)
  mode <- sample(1:3, 1)
  if (mode == 1) { od <- sample(1:3, 1); wts <- rep(1, 2 * od + 1); ordarg <- od }
  else if (mode == 2) { od <- f %/% 2; wts <- rep(1, 2 * od + 1); if (f == 2 * od) { wts[1] <- 0.5; wts[length(wts)] <- 0.5 }; ordarg <- "periodic" }
  else { wts <- round(runif(sample(c(3, 5), 1), 0.5, 2), 2); ordarg <- 1 }
  xs <- ts(x, frequency = f)
  r <- suppressWarnings(if (mode == 3) decaverage(xs, type = tn, times = tm, sides = sd, ends = c("NAs", "fill", "circular", "periodic")[en + 1], weights = wts) else decaverage(xs, type = tn, order = ordarg, times = tm, sides = sd, ends = c("NAs", "fill", "circular", "periodic")[en + 1]))
  for (w in 0:1) { v <- as.vector(r$series[, w + 1]); for (i in seq_along(v)) if (is.finite(v[i])) cases[[length(cases) + 1]] <- case("dec", c(4, 0, n, x, ty, tm, sd, en, w, i - 1, f, length(wts), wts), v[i], rel = 1e-9, abs = 1e-10) }
}
# decevf (kind 5: args (5, 0, n, x, type, lag, naxes, axes[naxes] (1-based), which, idx))
for (rep in 1:30) {
  n <- sample(40:120, 1); x <- round(cumsum(rnorm(n)) + 10 + 2 * sin(2 * pi * (1:n) / 12), 3); ty <- rep %% 2
  tn <- c("additive", "multiplicative")[ty + 1]; lag <- sample(4:8, 1); na <- sample(1:3, 1); axes <- sort(sample(1:min(lag, 4), na))
  r <- decevf(ts(x), type = tn, lag = lag, axes = axes)
  for (w in 0:1) { v <- as.vector(r$series[, w + 1]); for (i in seq_along(v)) if (is.finite(v[i])) cases[[length(cases) + 1]] <- case("dec", c(5, 0, n, x, ty, lag, na, axes, w, i - 1), v[i], rel = 1e-7, abs = 1e-8) }
}
# trend.test (kind 6: args (6, 0, n, x); fn "tt_rho" "tt_s" "tt_p"); series with and without ties, short (exact, n <= 9 and the Edgeworth range) and long
for (rep in 1:40) {
  n <- sample(c(5:9, 10:40, 60), 1); x <- if (rep %% 2 == 0) round(cumsum(rnorm(n)), 1) else cumsum(rnorm(n)) + (if (rep %% 3 == 0) 0 else seq_len(n) * 0.3)
  r <- trend.test(x)
  a <- c(6, 0, n, x)
  cases[[length(cases) + 1]] <- case("tt_rho", a, unname(r$estimate), rel = 1e-9, abs = 1e-10)
  cases[[length(cases) + 1]] <- case("tt_s", a, unname(r$statistic), rel = 1e-9, abs = 1e-9)
  cases[[length(cases) + 1]] <- case("tt_p", a, r$p.value, rel = 1e-8, abs = 1e-12)
}
# regul (fn "reg", args (6, 0, nx, x, y[nx], xmin, n, deltat, method, rule, f, window, idx)): method 0 constant 1 linear 2 area
for (rep in 1:60) {
  nx <- sample(8:30, 1); x <- sort(round(runif(nx, 0, 20), 2)); x <- unique(x); nx <- length(x); y <- round(rnorm(nx, 5, 2), 3)
  xmin <- if (rep %% 3 == 0) round(min(x) - 1, 2) else min(x); no <- sample(6:40, 1); dt <- round((max(x) - min(x)) / (no - 1) * c(1, 0.8, 1.1)[rep %% 3 + 1], 4)
  meth <- rep %% 3; ru <- sample(1:2, 1); f <- c(0, 0.5, 1)[sample(3, 1)]; win <- round(dt * c(1, 1.5, 2)[sample(3, 1)], 4)
  r <- suppressMessages(regul(x, y, xmin = xmin, n = no, deltat = dt, methods = c("constant", "linear", "area")[meth + 1], rule = ru, f = f, window = win, tol = 0))
  v <- r$y[[1]]
  for (i in seq_along(v)) if (is.finite(v[i])) cases[[length(cases) + 1]] <- case("reg", c(6, 0, nx, x, y, xmin, no, dt, meth, ru, f, win, i - 1), v[i], rel = 1e-9, abs = 1e-10)
}
# pgleissberg (fn "pg", args (7, 0, 0, n, k, lower, two.tailed)) and pennington (fn "pen", args (8, 0, nx, x, calc): 0 mean, 1 var, 2 mean.var)
for (n in c(3:49, 50, 60, 100, 250)) for (k in 0:(n - 2)) for (lt in 0:1) {
  if (n > 60 && k %% 7 != 0) next
  cases[[length(cases) + 1]] <- case("pg", c(7, 0, 0, n, k, lt, 0), pgleissberg(n, k, lower.tail = lt == 1), rel = 1e-9, abs = 1e-12)
}
for (n in c(4:49, 55, 100)) for (k in unique(c(0:(n - 2))[c(TRUE, FALSE, FALSE)])) {
  v <- tryCatch(pgleissberg(n, k, two.tailed = TRUE), error = function(e) NA)
  if (is.finite(v)) cases[[length(cases) + 1]] <- case("pg", c(7, 0, 0, n, k, 1, 1), v, rel = 1e-9, abs = 1e-12)
}
for (rep in 1:60) {
  nx <- sample(2:40, 1); x <- ifelse(runif(nx) < c(0, 0.3, 0.6)[rep %% 3 + 1], 0, round(rlnorm(nx, 1, c(0.5, 1, 1.5)[sample(3, 1)]), 3))
  for (ca in 0:2) { v <- pennington(x, calc = c("mean", "var", "mean.var")[ca + 1]); if (is.finite(v)) cases[[length(cases) + 1]] <- case("pen", c(8, 0, nx, x, ca), unname(v), rel = 1e-9, abs = 1e-12) }
}
# local.trend (fn "lt", args (9, k, n, x, q)) and escouf (fn "esc", args (10, level, n*p, x column-major, n, p, q): q 0 count, 1..count vr, count+1.. RV)
for (rep in 1:30) {
  n <- sample(5:40, 1); x <- round(cumsum(rnorm(n)) + 5, 3); k <- if (rep %% 2 == 0) mean(x) else round(runif(1, 3, 7), 2)
  v <- as.vector(local.trend(x, k = k, plotit = FALSE))
  for (q in seq_len(n)) cases[[length(cases) + 1]] <- case("lt", c(9, k, n, x, q - 1), v[q], rel = 1e-9, abs = 1e-10)
}
for (rep in 1:40) {
  n <- sample(15:60, 1); p <- sample(3:8, 1); B <- matrix(rnorm(p * p), p, p); X <- round(matrix(rnorm(n * p), n, p) %*% B, 3)
  df <- as.data.frame(X); lv <- c(1, 0.95, 0.9, 0.8)[rep %% 4 + 1]
  r <- suppressMessages(escouf(df, level = lv, verbose = FALSE)); cnt <- length(r$vr)
  out <- c(cnt, unname(r$vr), unname(r$RV))
  for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("esc", c(10, lv, n * p, as.vector(X), n, p, q - 1), out[q], rel = 1e-9, abs = 1e-10)
}
# abund (fn "ab", args (11, f, q*p, x column-major, q, p, k): vr, sort, cumsum, p.log.ind, p.nonull) and turnogram with FUN = mean
# (fn "tg", args (12, 0, n, x, imin, imax, step, complete, two.tailed, k): m, interval, n, turns, info, level, then for complete turns.min, turns.max, info.min, info.max)
for (rep in 1:30) {
  q <- sample(8:40, 1); p <- sample(3:9, 1); X <- matrix(rpois(q * p, rep(c(0.2, 1, 5), length.out = p)), q, p); X[, 1] <- X[, 1] + 1
  X <- X[, colSums(X) > 0, drop = FALSE]; p <- ncol(X); if (p < 3) next
  f <- c(0.2, 0.5, 0.8, 0.05)[rep %% 4 + 1]; r <- abund(as.data.frame(X), f = f)
  out <- c(unname(r$vr), unname(r$sort), unname(r$cumsum), unname(r$p.log.ind), unname(r$p.nonull))
  for (k in seq_along(out)) if (is.finite(out[k])) cases[[length(cases) + 1]] <- case("ab", c(11, f, q * p, as.vector(X), q, p, k - 1), out[k], rel = 1e-9, abs = 1e-10)
}
for (rep in 1:40) {
  n <- sample(60:200, 1); x <- round(cumsum(rnorm(n)) + 10 + 2 * sin(2 * pi * seq_len(n) / 12), 3)
  imax <- sample(4:floor(n / 5), 1); cm <- rep %% 2 == 0; tw <- rep %% 4 < 2
  r <- suppressWarnings(turnogram(ts(x), intervals = c(1, imax), complete = cm, two.tailed = tw, plotit = FALSE))
  out <- c(length(r$interval), r$interval, r$n, r$turns, r$info, r$level); if (cm) out <- c(out, r$turns.min, r$turns.max, r$info.min, r$info.max)
  for (k in seq_along(out)) if (is.finite(out[k])) cases[[length(cases) + 1]] <- case("tg", c(12, 0, n, x, 1, imax, 1, as.numeric(cm), as.numeric(tw), k - 1), out[k], rel = 1e-7, abs = 1e-9)
}
# deccensus (fn "cen", args (13, 0, n, x, period, q): test.s, amplitude, deseasoned, seasonal, trend, residuals)
for (rep in 1:30) {
  per <- c(4, 12, 6, 12)[rep %% 4 + 1]; nc <- sample(5:10, 1); n <- per * nc
  x <- round(exp(0.02 * seq_len(n) + 0.3 * sin(2 * pi * seq_len(n) / per) + rnorm(n, 0, c(0.05, 0.2, 0.4)[rep %% 3 + 1])) * 10, 4)
  r1 <- tryCatch(suppressWarnings(deccensus(ts(x, frequency = per), trend = FALSE)), error = function(e) NULL); r2 <- tryCatch(suppressWarnings(deccensus(ts(x, frequency = per), trend = TRUE)), error = function(e) NULL)
  if (is.null(r1) || is.null(r2) || is.null(r1$amplitude) || !is.matrix(r1$series)) next
  out <- c(r1$test.seasons, r1$amplitude, r1$series[, 1], r1$series[, 2], r2$series[, 1], r2$series[, 3])
  for (k in seq_along(out)) if (is.finite(out[k])) cases[[length(cases) + 1]] <- case("cen", c(13, 0, n, x, per, k - 1), out[k], rel = 1e-9, abs = 1e-10)
}
# regul with the spline method (fn "regsp", args (14, 0, nx, x, y[nx], xmin, n, deltat, rule, idx))
for (rep in 1:40) {
  nx <- sample(8:30, 1); x <- sort(round(runif(nx, 0, 20), 2)); x <- unique(x); nx <- length(x); y <- round(rnorm(nx, 5, 2), 3)
  xmin <- if (rep %% 3 == 0) round(min(x) - 1, 2) else min(x); no <- sample(6:40, 1); dt <- round((max(x) - min(x)) / (no - 1) * c(1, 0.8, 1.1)[rep %% 3 + 1], 4); ru <- sample(1:2, 1)
  r <- suppressMessages(regul(x, y, xmin = xmin, n = no, deltat = dt, methods = "spline", rule = ru, tol = 0)); v <- r$y[[1]]
  for (i in seq_along(v)) if (is.finite(v[i])) cases[[length(cases) + 1]] <- case("regsp", c(14, 0, nx, x, y, xmin, no, dt, ru, i - 1), v[i], rel = 1e-9, abs = 1e-10)
}
# regul with a matching tolerance (fn "regtol", args (15, 0, nx, x, y, xmin, n, deltat, method, rule, f, window, tol, tol.type, idx)): method 0 constant 1 linear 2 area 3 spline; tol.type 0 left 1 both 2 right 3 none
tt <- c("left", "both", "right", "none")
for (rep in 1:80) {
  nx <- sample(8:30, 1); x <- sort(round(runif(nx, 0, 20), 2)); x <- unique(x); nx <- length(x); y <- round(rnorm(nx, 5, 2), 3)
  xmin <- if (rep %% 3 == 0) round(min(x) - 1, 2) else min(x); no <- sample(6:40, 1); dt <- round((max(x) - min(x)) / (no - 1) * c(1, 0.8, 1.1)[rep %% 3 + 1], 4)
  meth <- rep %% 4; ru <- sample(1:2, 1); f <- c(0, 0.5, 1)[sample(3, 1)]; win <- round(dt * c(1, 1.5, 2)[sample(3, 1)], 4)
  tl <- round(dt * c(0.1, 0.25, 0.5, 0.8, 1.5)[sample(5, 1)], 4); ty <- sample(0:3, 1)
  r <- tryCatch(suppressMessages(capture.output(rr <- regul(x, y, xmin = xmin, n = no, deltat = dt, methods = c("constant", "linear", "area", "spline")[meth + 1], rule = ru, f = f, window = win, tol = tl, tol.type = tt[ty + 1]))), error = function(e) NULL)
  if (is.null(r)) next
  v <- rr$y[[1]]
  for (i in seq_along(v)) if (is.finite(v[i])) cases[[length(cases) + 1]] <- case("regtol", c(15, 0, nx, x, y, xmin, no, dt, meth, ru, f, win, tl, ty, i - 1), v[i], rel = 1e-9, abs = 1e-10)
}
# regul.screen for one start and step (fn "scr", args (16, 0, nx, x, weight, xmin, deltat, tol, tol.type, field)): 0 tol, 1 nx, 2 match, 3 exact.match
for (rep in 1:60) {
  nx <- sample(10:40, 1); x <- sort(unique(round(runif(nx, 0, 20), 2))); nx <- length(x); w <- round(runif(nx, 0.5, 3), 2)
  xmin <- if (rep %% 2 == 0) min(x) else round(min(x) - runif(1, 0, 1), 2); dt <- round(runif(1, 0.3, 2.5), 3); tl <- round(dt * c(0.1, 0.2, 0.5, 1.4)[sample(4, 1)], 4); ty <- sample(0:3, 1)
  r <- tryCatch(regul.screen(x, weight = w, xmin = xmin, deltat = dt, tol = tl, tol.type = tt[ty + 1]), error = function(e) NULL); if (is.null(r)) next
  out <- c(unname(r$tol), r$n[1, 1], r$nbr.match[1, 1], r$nbr.exact.match[1, 1])
  for (k in 0:3) cases[[length(cases) + 1]] <- case("scr", c(16, 0, nx, x, w, xmin, dt, tl, ty, k), out[k + 1], rel = 1e-9, abs = 1e-10)
}
# regul with the periodic spline (fn "regtol" with method 4, tol 0)
for (rep in 1:40) {
  nx <- sample(6:25, 1); x <- sort(round(runif(nx, 0, 20), 2)); x <- unique(x); nx <- length(x); y <- round(rnorm(nx, 5, 2), 3); y[nx] <- y[1]
  if (rep %% 2 == 0) y[nx] <- round(y[1] + 0.3, 3)
  xmin <- if (rep %% 3 == 0) round(min(x) - 1, 2) else min(x); no <- sample(6:40, 1); dt <- round((max(x) - min(x)) / (no - 1) * c(1, 0.8, 1.1)[rep %% 3 + 1], 4); ru <- sample(1:2, 1)
  r <- tryCatch(suppressWarnings(suppressMessages(regul(x, y, xmin = xmin, n = no, deltat = dt, methods = "spline", rule = ru, periodic = TRUE, tol = 0))), error = function(e) NULL); if (is.null(r)) next
  v <- r$y[[1]]
  for (i in seq_along(v)) if (is.finite(v[i])) cases[[length(cases) + 1]] <- case("regtol", c(15, 0, nx, x, y, xmin, no, dt, 4, ru, 0, dt, 0, 1, i - 1), v[i], rel = 1e-9, abs = 1e-10)
}
# stl (fn "stl", args (17, 0, n, y, period, periodic, s.window, s.degree, t.window, t.degree, l.window, l.degree, s.jump, t.jump, l.jump, robust, which, idx): which 0 seasonal 1 trend 2 weights 3 remainder; zero windows and jumps are the defaults)
for (rep in 1:50) {
  per <- c(4, 12, 7, 6)[rep %% 4 + 1]; nc <- sample(4:9, 1); n <- per * nc; y <- round(10 + 0.1 * seq_len(n) + 3 * sin(2 * pi * seq_len(n) / per) + rnorm(n), 4)
  periodic <- rep %% 3 == 0; sw <- if (periodic) 0 else c(7, 9, 13, 21)[sample(4, 1)]; sd <- sample(0:1, 1); tw <- c(0, 15, 25)[sample(3, 1)]; td <- sample(0:1, 1); lw <- c(0, 9)[sample(2, 1)]; ld <- td
  sj <- c(0, 1, 2)[sample(3, 1)]; tj <- c(0, 1, 3)[sample(3, 1)]; lj <- c(0, 1)[sample(2, 1)]; rb <- rep %% 5 == 0
  args <- list(ts(y, frequency = per), s.window = if (periodic) "periodic" else sw, s.degree = sd, t.degree = td, l.degree = ld, robust = rb)
  if (tw > 0) args$t.window <- tw; if (lw > 0) args$l.window <- lw; if (sj > 0) args$s.jump <- sj; if (tj > 0) args$t.jump <- tj; if (lj > 0) args$l.jump <- lj
  r <- tryCatch(do.call(stats::stl, args), error = function(e) NULL); if (is.null(r)) next
  ts_ <- r$time.series; outs <- list(as.vector(ts_[, "seasonal"]), as.vector(ts_[, "trend"]), as.vector(r$weights), as.vector(ts_[, "remainder"]))
  for (w in 0:3) for (i in seq_len(n)) cases[[length(cases) + 1]] <- case("stl", c(17, 0, n, y, per, as.numeric(periodic), sw, if (periodic) 0 else sd, tw, td, lw, ld, sj, tj, lj, as.numeric(rb), w, i - 1), outs[[w + 1]][i], rel = 1e-8, abs = 1e-9)
}
emit("pastecs", "pastecs", list(cases))
