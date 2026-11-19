# mgcv: gam(y ~ s(x, bs = "cr"/"ps", k = k), sp = sp) for a Gaussian response with a fixed smoothing parameter. Args: (n, k, bs (0 cr, 1 ps), sp, what, idx, x[n], y[n]):
# what 0 coef[idx], 1 fitted[idx], 2 the total edf, 3 sig2, 4 the GCV score (gcv.ubre), 5 the residual sum of squares.
suppressMessages(library(mgcv))
cases <- list()
set.seed(20262303)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("gam", args, want, rel = 1e-7, abs = 1e-9)
for (rep in 1:12) {
  n <- sample(40:90, 1); k <- sample(6:12, 1); bs <- rep %% 2; sp <- 10^runif(1, -3, 2)
  x <- sort(round(runif(n, 0, 10), 3)); y <- round(sin(x) + 0.3 * x + rnorm(n, 0, 0.4), 4)
  f <- gam(y ~ s(x, bs = if (bs == 0) "cr" else "ps", k = k), sp = sp)
  hdr <- function(w, i) c(n, k, bs, sp, w, i, x, y)
  for (i in seq_along(f$coefficients)) add(hdr(0, i - 1), f$coefficients[i])
  for (i in seq_len(n)) add(hdr(1, i - 1), f$fitted.values[i])
  add(hdr(2, 0), sum(f$edf)); add(hdr(3, 0), f$sig2); add(hdr(4, 0), f$gcv.ubre); add(hdr(5, 0), sum(f$residuals^2))
}
emit("mgcv_gam", "mgcv", list(cases))
