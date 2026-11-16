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
emit("pastecs", "pastecs", list(cases))
