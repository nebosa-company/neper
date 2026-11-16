# laeken: weighted quantiles and the poverty and inequality indicators.
#   args: (n, has_sort, p, inc[n], weights[n], sort[n]); p is the probability (quant), k (quint) or the arpt level
#   fn "quant" weightedQuantile at p; "median"; "wmean"; "quint" incQuintile k = p; "gini" "qsr" "arpt" (level p) "arpr" (threshold arpt(p)) "rmpg"
suppressMessages(library(laeken))
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-10, abs = 1e-10)
set.seed(20261125)
for (rep in 1:10) {
  n <- c(40, 75, 120, 33, 200)[(rep - 1) %% 5 + 1]
  inc <- round(rlnorm(n, 10, 0.7) / 50) * 50; w <- round(runif(n, 0.5, 3), 3); so <- sample(1:3, n, TRUE)
  for (hs in 0:1) {
    sortv <- if (hs) so else NULL; a <- function(p) c(n, hs, p, inc, w, so)
    add("gini", a(0), gini(inc, weights = w, sort = sortv)$value); add("qsr", a(0), qsr(inc, weights = w, sort = sortv)$value)
    for (k in 1:4) add("quint", a(k), incQuintile(inc, weights = w, sort = sortv, k = k))
    for (p in c(0.5, 0.6)) {
      add("arpt", a(p), arpt(inc, weights = w, sort = sortv, p = p)); add("arpr", a(p), arpr(inc, weights = w, sort = sortv, p = p)$value)
    }
    add("rmpg", a(0.6), rmpg(inc, weights = w, sort = sortv)$value)
  }
  for (p in c(0, 0.1, 0.5, 0.75, 0.999, 1)) add("quant", c(n, 0, p, inc, w, so), weightedQuantile(inc, w, probs = p))
  add("median", c(n, 0, 0, inc, w, so), weightedMedian(inc, w)); add("wmean", c(n, 0, 0, inc, w, so), weightedMean(inc, w))
}
emit("laeken", "laeken", list(cases))
