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
#   hexTapply: "tap" (xbins, shape, n, x, y, fun, j) with fun 0 sum 1 mean 2 length 3 min 4 max over y; smooth.hexbin: "scell" "scount" "scx" "scy"
#   (xbins, shape, n, x, y, w1, w2, w3, j) and "sdim" j 0 1; erode.hexbin: "erode" over the selected cells and "eroded" (xbins, shape, n, x, y, cdfcut, j)
funs <- list(sum, mean, length, min, max)
for (rep in 1:6) {
  n <- c(50, 90, 140, 70, 110, 120)[rep]
  x <- round(c(rnorm(n %/% 2), rnorm(n - n %/% 2, 3)) * (1 + rep / 7), 3); y <- round(x * 0.5 + rnorm(n), 3)
  for (xbins in c(8, 20)) for (shape in c(1, 0.6)) {
    h <- hexbin(x, y, xbins = xbins, shape = shape, IDs = TRUE)
    a <- c(xbins, shape, n, x, y)
    for (fi in 0:4) vec("tap", c(a, fi), as.numeric(hexTapply(h, y, funs[[fi + 1]])))
    for (w in list(c(48, 4, 1), c(6, 1, 0), c(10, 2, 1))) {
      s <- smooth.hexbin(h, wts = w); b <- c(a, w)
      vec("scell", b, s@cell); vec("scount", b, s@count); xy <- hcell2xy(s); vec("scx", b, xy$x); vec("scy", b, xy$y)
      add("sdim", c(b, 0), s@dimen[1]); add("sdim", c(b, 1), s@dimen[2])
    }
    for (cut in c(0.2, 0.5, 0.9)) {
      e <- erode(h, cdfcut = cut); if (is.character(e)) next
      vec("erode", c(a, cut), as.numeric(e@erode)); vec("eroded", c(a, cut), as.numeric(e@eroded))
    }
  }
}
emit("hexbin", "hexbin", list(cases))
