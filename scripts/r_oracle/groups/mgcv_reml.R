# mgcv: gam(y ~ s(x, bs = "cr"/"ps", k = k)) with the smoothing parameter chosen by REML (method = "REML"). Args: (n, k, bs (0 cr, 1 ps), what, idx, x[n], y[n]):
# what 0 the REML score at the selected sp (gcv.ubre), 1 the total edf, 2 fitted[idx], 3 the selected sp (log10, compared loosely: the optimiser stops at a score tolerance).
suppressMessages(library(mgcv))
cases <- list()
set.seed(20262305)
add <- function(args, want, rel = 1e-5, abs = 1e-8) cases[[length(cases) + 1]] <<- case("reml", args, want, rel = rel, abs = abs)
for (rep in 1:10) {
  n <- sample(50:100, 1); k <- sample(8:14, 1); bs <- rep %% 2
  x <- sort(round(runif(n, 0, 10), 3)); y <- round(sin(x) + 0.3 * x + rnorm(n, 0, 0.4), 4)
  f <- gam(y ~ s(x, bs = if (bs == 0) "cr" else "ps", k = k), method = "REML")
  hdr <- function(w, i) c(n, k, bs, w, i, x, y)
  add(hdr(0, 0), as.numeric(f$gcv.ubre), rel = 1e-6); add(hdr(1, 0), sum(f$edf), rel = 1e-3)
  for (i in seq(1, n, by = 7)) add(hdr(2, i - 1), f$fitted.values[i], rel = 1e-3, abs = 1e-4)
  add(hdr(3, 0), log10(f$sp), rel = 0, abs = 0.05)
}
emit("mgcv_reml", "mgcv", list(cases))
