# KernSmooth::locpoly (normal kernel, scalar bandwidth, y given, truncate = TRUE): the fitted grid summarised.
#   args: (n, drv, degree, h, M, x[n], y[n]) fn "sum" "w" "first" "mid" "last"
suppressMessages(library(KernSmooth))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-9)
set.seed(20261116)
for (rep in 1:30) {
  n <- sample(30:120, 1); x <- round(runif(n, 0, 10), 3); y <- round(sin(x) + rnorm(n, 0, 0.3), 3)
  drv <- sample(0:2, 1); degree <- drv + sample(1:2, 1); M <- sample(c(101, 201, 401), 1); h <- round(runif(1, 0.5, 1.5), 3)
  r <- tryCatch(locpoly(x, y, drv = drv, degree = degree, bandwidth = h, gridsize = M), error = function(e) NULL)
  if (is.null(r) || any(!is.finite(r$y))) next
  a <- c(n, drv, degree, h, M, x, y)
  add("sum", a, sum(r$y)); add("w", a, sum(seq_along(r$y) * r$y)); add("first", a, r$y[1]); add("mid", a, r$y[(M + 1) %/% 2]); add("last", a, r$y[M])
}
emit("locpoly", "KernSmooth", list(cases))
