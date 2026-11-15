# classInt::classIntervals break rules that need no random numbers. A vector answer is one case per
# element (fn "v:<style>") plus a length case ("len:<style>"); the last argument of an element case is its position.
#   args: (style, n, extra, len, x..., [pos])   style 0 equal 1 pretty 2 sd 3 quantile (extra = type) 4 jenks 5 fisher
#   6 headtails (n unused, extra = thr) 7 maximum 8 box (extra = iqr_mult, n = quantile type, legacy in n >= 100) 
#   "cols": (left, x, nb, brks...) -> the 0-based class of x from findCols, -1 outside
suppressMessages(library(classInt))
set.seed(20261115)
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-11, abs = 1e-12)
vec <- function(name, args, v) {
  add(paste0("len:", name), args, length(v))
  for (i in seq_along(v)) add(paste0("v:", name), c(args, i - 1), v[i])
}
quiet <- function(f) tryCatch(suppressWarnings(suppressMessages(f)), error = function(e) NULL)
xs <- list(round(runif(40, 0, 100), 3), round(rnorm(60, 50, 12), 2), round(rexp(80) * 10, 2), as.numeric(1:10),
           round(rlnorm(100, 2, 1), 3), round(rnorm(50) * 3), c(1, 2, 4, 8, 16, 32, 64, 100), round(runif(25, -5, 5), 1),
           c(rnorm(30, 10), rnorm(30, 40, 3)))
cls <- function(x, n, style, ...) quiet(classIntervals(x, n, style = style, warnSmallN = FALSE, ...)$brks)
for (x in xs) {
  nobs <- length(unique(x))
  for (n in c(2, 3, 4, 5, 6, 8)) {
    if (n >= nobs) next
    len <- length(x)
    for (st in list(list(0, "equal"), list(1, "pretty"), list(2, "sd"), list(4, "jenks"), list(5, "fisher"), list(7, "maximum"))) {
      b <- cls(x, n, st[[2]])
      if (!is.null(b)) vec(st[[2]], c(st[[1]], n, 0, len, x), b)
    }
    for (ty in 1:9) {
      b <- cls(x, n, "quantile", type = ty)
      if (!is.null(b)) vec("quantile", c(3, n, ty, len, x), b)
    }
  }
  for (thr in c(0.4, 0.25, 0.6)) { b <- cls(x, 4, "headtails", thr = thr); if (!is.null(b)) vec("headtails", c(6, 0, thr, length(x), x), b) }
  for (ty in c(7, 6, 2)) for (mult in c(1.5, 3)) for (lg in c(FALSE, TRUE)) {
    b <- cls(x, 4, "box", iqr_mult = mult, type = ty, legacy = lg)
    if (!is.null(b)) vec("box", c(8, ty + if (lg) 100 else 0, mult, length(x), x), b)
  }
  for (n in c(3, 5)) {
    if (n >= nobs) next
    b <- cls(x, n, "quantile")
    for (left in c(1, 0)) {
      ic <- if (left == 1) "left" else "right"
      v <- c(sample(x, 6), min(x), max(x), b[2], mean(x), min(x) - 1)
      res <- quiet(classIntervals(x, n, style = "quantile", intervalClosure = ic, warnSmallN = FALSE))
      cl <- findCols(res)
      for (xx in x[1:8]) add("cols", c(left, xx, length(b), b), findInterval(xx, b, left.open = left == 0, rightmost.closed = TRUE) - 1)
    }
  }
}
emit("classint", "classInt", list(cases))
