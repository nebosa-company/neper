# splinepkg: stats::spline with method "fmm" and "natural" at points inside the data range.
#   args: (method 0 fmm 1 natural, index, n, x (n, ascending), y (n), 4 evaluation points) answering spline(x, y, xout = points, method)$y[index + 1]
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-11)
set.seed(20262023)
for (rep in 1:40) {
  n <- sample(2:14, 1); x <- sort(runif(n, 0, 10)); y <- round(cumsum(rnorm(n)), 4)
  pts <- if (n >= 2) runif(4, min(x), max(x)) else numeric(0)
  for (m in 0:1) {
    s <- spline(x, y, xout = pts, method = c("fmm", "natural")[m + 1])$y
    for (i in 1:4) add("spline", c(m, i - 1, n, x, y, pts), s[i])
  }
}
emit("splinepkg", "stats", list(cases))
