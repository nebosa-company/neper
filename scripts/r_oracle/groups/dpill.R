# KernSmooth: dpill and bkde2D.
#   dpill: (n, x[n], y[n], blockmax, divisor, trim, proptrun, gridsize) fn "dpill"
#   bkde2D: (n, h1, h2, m1, m2, x row-major[n*2], q) fn "bkde2d"  q 0 sum 1 weighted sum of fhat (row-major) 2 max
suppressMessages(library(KernSmooth))
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-7, abs = 1e-10)
set.seed(20261118)
for (rep in 1:40) {
  n <- sample(60:300, 1); x <- sort(round(runif(n, 0, 1), 4)); y <- round(sin(2 * pi * x) + rnorm(n, 0, 0.3), 4)
  bm <- sample(3:6, 1); dv <- sample(c(15, 20, 25), 1); tr <- sample(c(0.01, 0.02), 1); pt <- sample(c(0.05, 0.1), 1); gs <- sample(c(201, 401), 1)
  h <- tryCatch(dpill(x, y, blockmax = bm, divisor = dv, trim = tr, proptrun = pt, gridsize = gs), error = function(e) NA)
  add("dpill", c(n, x, y, bm, dv, tr, pt, gs), h)
}
for (rep in 1:30) {
  n <- sample(30:200, 1); m1 <- sample(c(21, 31, 51), 1); m2 <- sample(c(21, 41), 1)
  x <- cbind(round(rnorm(n), 4), round(rnorm(n, 1, 2), 4)); h1 <- runif(1, 0.2, 0.8); h2 <- runif(1, 0.3, 1.2)
  r <- tryCatch(bkde2D(x, c(h1, h2), gridsize = c(m1, m2)), error = function(e) NULL)
  if (is.null(r)) next
  v <- as.vector(t(r$fhat)); a <- c(n, h1, h2, m1, m2, as.vector(t(x)))
  add("bkde2d", c(a, 0), sum(v)); add("bkde2d", c(a, 1), sum(seq_along(v) * v)); add("bkde2d", c(a, 2), max(v))
}
emit("dpill", "KernSmooth", list(cases))
