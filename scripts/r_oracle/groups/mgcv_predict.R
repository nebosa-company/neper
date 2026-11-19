# mgcv: predict.gam(se.fit = TRUE) for gam(y ~ s(x, bs = "cr", k = k), sp = sp) at new covariate values inside the data range. Args: (n, k, m, sp, what, idx, x[n], y[n], xnew[m]):
# what 0 the prediction at xnew[idx], 1 its standard error.
suppressMessages(library(mgcv))
cases <- list()
set.seed(20262307)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("pr", args, want, rel = 1e-7, abs = 1e-9)
for (rep in 1:10) {
  n <- sample(40:90, 1); k <- sample(6:12, 1); sp <- 10^runif(1, -2, 1.5)
  x <- sort(round(runif(n, 0, 10), 3)); y <- round(sin(x) + 0.3 * x + rnorm(n, 0, 0.4), 4)
  f <- gam(y ~ s(x, bs = "cr", k = k), sp = sp)
  m <- 15; xnew <- round(runif(m, min(x), max(x)), 3)
  pr <- predict(f, data.frame(x = xnew), se.fit = TRUE)
  hdr <- function(w, i) c(n, k, m, sp, w, i, x, y, xnew)
  for (i in seq_len(m)) { add(hdr(0, i - 1), pr$fit[i]); add(hdr(1, i - 1), pr$se.fit[i]) }
}
emit("mgcv_predict", "mgcv", list(cases))
