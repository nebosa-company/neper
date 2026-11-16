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
emit("pastecs", "pastecs", list(cases))
