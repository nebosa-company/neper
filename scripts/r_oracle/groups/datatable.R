# data.table algorithms: froll*, shift, rleid, between, inrange, foverlaps, order. Vector answers are one
# case per element (fn "v:<name>") plus a length case (fn "len:<name>").
#   froll:    args (kind 0 mean 1 sum 2 max 3 min 4 median, align 0 right 1 left 2 center, fill, na_rm, adaptive, n, len, x..., [n vector])
#   shift:    args (n, fill, type 0 lag 1 lead 2 cyclic, len, x...)       rleid: args (len, x...)
#   between:  args (lower, upper, inc, len, x...)     inrange: args (inc, nranges, lower..., upper..., len, x...)
#   overlaps: args (type, mult, nx, xs..., xe..., ny, ys..., ye...)   order: args (decreasing, na_last 1 | 0, len, x...)
library(data.table)
set.seed(20261115)
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-12, abs = 1e-13)
vec <- function(name, args, v) {
  add(paste0("len:", name), args, length(v))
  for (i in seq_along(v)) add(paste0("v:", name), c(args, i - 1), v[i])
}
xs <- list(c(1, 2, 3, 4, 5, 6, 7), c(1, 2, NA, 4, 5, 6, 7), c(5, 3, 8, 1, 9, 2), c(1e10, 1, -1e10, 2, 3), c(NA, NA, 3, 4), c(2, 2, 2, 2), c(7), c(-1.5, 0.25, 8, -3, 4.5, 4.5, 0))
aligns <- c("right", "left", "center")
for (x in xs[-4]) for (n in 1:5) for (al in 1:3) for (na in c(FALSE, TRUE)) for (fill in c(NA, 0)) {   # [-4]: 1e10, 1, -1e10 drifts in data.table itself
  a0 <- c(0, al - 1, fill, na, 0, n, length(x), x)
  g <- function(k, v) vec("froll", c(k, a0[-1]), v)
  fl <- aligns[al]
  r <- function(f) tryCatch(suppressWarnings(f), error = function(e) NULL)
  v <- r(frollmean(x, n, fill = fill, algo = "exact", align = fl, na.rm = na)); if (!is.null(v)) g(0, v)
  v <- r(frollsum(x, n, fill = fill, algo = "exact", align = fl, na.rm = na)); if (!is.null(v)) g(1, v)
  v <- r(frollmax(x, n, fill = fill, algo = "exact", align = fl, na.rm = na)); if (!is.null(v)) g(2, v)
  v <- r(frollmin(x, n, fill = fill, algo = "exact", align = fl, na.rm = na)); if (!is.null(v)) g(3, v)
  v <- r(frollapply(x, n, function(w) median(w, na.rm = na), fill = fill, align = fl)); if (!is.null(v)) g(4, v)
}
for (x in xs[c(1, 3, 8)]) for (fill in c(NA, 0)) {
  nv <- sample(1:4, length(x), replace = TRUE)
  for (k in 0:2) {
    f <- list(frollmean, frollsum, frollmax)[[k + 1]]
    v <- tryCatch(suppressWarnings(f(x, nv, fill = fill, algo = "exact", adaptive = TRUE)), error = function(e) NULL)
    if (!is.null(v)) vec("froll", c(k, 0, fill, 0, 1, 0, length(x), x, nv), v)
  }
}
for (x in xs) for (n in c(-2, -1, 1, 2, 3)) for (fill in c(NA, 9)) for (ty in 0:2) {
  tn <- c("lag", "lead", "cyclic")[ty + 1]
  nn <- if (ty == 1) -n else n   # lead of k is shift(n = -k) in the lag convention: keep the same call both sides
  v <- tryCatch(shift(x, n = n, fill = fill, type = tn), error = function(e) NULL)
  if (!is.null(v) && ty != 2) vec("shift", c(n, fill, ty, length(x), x), v) else if (!is.null(v)) vec("shift", c(n, fill, 2, length(x), x), v)
}
for (x in list(c(1, 1, 2, 2, 1, NA, NA), c(3, 3, 3), c(1, 2, 3), c(NA, 1, NA), c(5), c(0, -0, 1))) vec("rleid", c(length(x), x), as.numeric(rleid(x)))
for (x in list(c(1, 5, NA, 10, 2, 8), c(-3, 0, 3))) for (lo in c(2, NA, -5)) for (up in c(8, NA, 3)) for (inc in c(TRUE, FALSE)) {
  v <- as.numeric(between(x, lo, up, incbounds = inc)); vec("between", c(lo, up, inc, length(x), x), v)
}
for (x in list(c(1, 5, 10, 6), c(0, 12))) for (inc in c(TRUE, FALSE)) {
  lo <- c(0, 6); up <- c(2, 12)
  vec("inrange", c(inc, 2, lo, up, length(x), x), as.numeric(inrange(x, lo, up, incbounds = inc)))
}
mk <- function(n, hi) { s <- sample(0:hi, n, replace = TRUE); data.table(s = s, e = s + sample(0:5, n, replace = TRUE)) }
for (rep_ in 1:25) {
  x <- mk(sample(1:6, 1), 12); y <- mk(sample(1:6, 1), 12); y <- y[order(s, e)]
  yk <- copy(y); setkey(yk, s, e)
  for (ty in c("any", "within", "start", "end", "equal")) for (mu in c("all", "first", "last")) {
    res <- tryCatch(suppressWarnings(foverlaps(x, yk, by.x = c("s", "e"), type = ty, mult = mu, which = TRUE)), error = function(e) NULL)
    if (is.null(res)) next
    if (is.data.table(res)) { xid <- res$xid; yid <- res$yid } else { xid <- seq_len(nrow(x)); yid <- res }
    ti <- match(ty, c("any", "within", "start", "end", "equal")) - 1; mi <- match(mu, c("all", "first", "last")) - 1
    a0 <- c(ti, mi, nrow(x), x$s, x$e, nrow(yk), yk$s, yk$e)
    add("len:overlaps", a0, length(xid))
    for (i in seq_along(xid)) { add("x:overlaps", c(a0, i - 1), xid[i]); add("y:overlaps", c(a0, i - 1), yid[i]) }
  }
}
for (x in list(c(3, NA, 1, 3, 2), c(5, 5, 5), c(2, 1), c(NA, NA, 1), c(4, 2, 2, 9, NA, 2))) for (dec in c(FALSE, TRUE)) for (nl in c(TRUE, FALSE)) {
  d <- data.table(x = x, i = seq_along(x))
  setorderv(d, "x", order = if (dec) -1L else 1L, na.last = nl)
  vec("order", c(dec, as.numeric(nl), length(x), x), d$i)
}
emit("datatable", "data.table", list(cases))
