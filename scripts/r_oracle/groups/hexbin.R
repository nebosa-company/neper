# hexbin: counts, cell ids, centres of mass and cell centres.
#   args: (xbins, shape, n, x..., y..., stat)   fn "cell" "count" "xcm" "ycm" "cx" "cy" (cell centres): stat 0 length 1 sum 2 position-weighted sum 3 first 4 last
#   "dims": (xbins, shape, n, x, y) -> imax, jmax by stat 0 / 1
suppressMessages(library(hexbin))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-10, abs = 1e-12)
set.seed(20261115)
vec <- function(fn, a, v) { v <- as.numeric(v); w <- seq_along(v); st <- c(length(v), sum(v), sum(w * v), v[1], v[length(v)]); for (j in 0:4) add(fn, c(a, j), st[j + 1]) }
for (rep in 1:6) {
  n <- c(30, 60, 100, 45, 80, 70)[rep]
  x <- round(c(rnorm(n %/% 2), rnorm(n - n %/% 2, 3)) * (1 + rep / 7), 3); y <- round(x * 0.5 + rnorm(n), 3)
  for (xbins in c(8, 30.5)) for (shape in c(1, 0.6)) {
    h <- hexbin(x, y, xbins = xbins, shape = shape)
    a <- c(xbins, shape, n, x, y)
    vec("cell", a, h@cell); vec("count", a, h@count); vec("xcm", a, h@xcm); vec("ycm", a, h@ycm)
    xy <- hcell2xy(h); vec("cx", a, xy$x); vec("cy", a, xy$y)
    add("dims", c(a, 0), h@dimen[1]); add("dims", c(a, 1), h@dimen[2])
  }
}
emit("hexbin", "hexbin", list(cases))
