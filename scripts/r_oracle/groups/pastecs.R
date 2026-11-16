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
emit("pastecs", "pastecs", list(cases))
