# labeling and scales: break algorithms, transformations and bounds helpers.
# Vector answers become one case per element (fn "name") plus a length case (fn "len:name").
#   labelers:   args (dmin, dmax, m [, only.loose])
#   pretty:     args (lo, hi, n)           breaks_extended / breaks_pretty: args (n, k, x...)
#   breaks_log: args (n, base, k, x...)    breaks_width: args (width, offset, k, x...)
#   transform:  args (kind, p, offset, sigma, base, mode, x)  mode 0 trans, 1 inverse, 2 d_trans, 3 d_inv
#   bounds:     rescale (x, to1, to2, from1, from2), rescale_mid (.., mid), rescale_max (x, to2, from2),
#               oob (x, lo, hi, rule), expand_range (lo, hi, mul, add, zerowidth, which), zero_range (lo, hi)
library(labeling)
library(scales)

cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-12, abs = 1e-14)
vec <- function(fn, args, v) {
  add(paste0("len:", fn), args, length(v))
  for (i in seq_along(v)) add(fn, c(args, i - 1), v[i])
}
try_vec <- function(fn, args, expr) {
  v <- tryCatch(suppressWarnings(expr), error = function(e) NULL)
  if (!is.null(v)) vec(fn, args, as.numeric(v))
}

ranges <- list(c(0, 1), c(0, 100), c(-3.7, 12.2), c(1234, 5678), c(0.001, 0.0049), c(-1e6, 3e6), c(99.5, 100.5),
               c(-5, 5), c(0.3, 0.7), c(17, 23), c(1e-3, 1e3), c(2, 2000), c(-0.02, 0.013), c(50, 60), c(3.1415, 27.18))
ms <- c(3, 4, 5, 6, 7, 10, 4.5)
for (r in ranges) for (m in ms) {
  a <- c(r, m)
  try_vec("heckbert", a, heckbert(r[1], r[2], m))
  try_vec("wilkinson", a, wilkinson(r[1], r[2], m))
  try_vec("nelder", a, nelder(r[1], r[2], m))
  try_vec("rpretty", a, rpretty(r[1], r[2], m))
  try_vec("extended", c(a, 0), extended(r[1], r[2], m))
  try_vec("extended", c(a, 1), extended(r[1], r[2], m, only.loose = TRUE))
  try_vec("pretty", c(r, round(m)), pretty(c(r[1], r[2]), round(m)))
}
for (r in list(c(0, 0), c(5, 5), c(-3, -3), c(0, 1e-12))) {
  try_vec("extended", c(r, 5, 0), extended(r[1], r[2], 5))
  try_vec("pretty", c(r, 5), pretty(c(r[1], r[2]), 5))
  try_vec("rpretty", c(r, 5), rpretty(r[1], r[2], 5))
}

xs <- list(c(1, 100), c(3, 3000), c(0.5, 7), c(10, 12), c(1, 1e6), c(0.001, 1000), c(2, 500), c(1, 1), c(15, 150), c(0.01, 10), c(1, 8), c(7, 7000))
for (x in xs) for (n in c(3, 5, 7)) {
  try_vec("breaks_extended", c(n, length(x), x), breaks_extended(n)(x))
  try_vec("breaks_pretty", c(n, length(x), x), breaks_pretty(n)(x))
  for (b in c(10, 2, exp(1), 5)) try_vec("breaks_log", c(n, b, length(x), x), breaks_log(n, b)(x))
}
for (x in list(c(1, 47), c(0.3, 8.8), c(-12, 35), c(100, 100), c(5, 5.5)))
  for (w in c(1, 5, 0.25, 10)) for (o in c(0, 2.5))
    try_vec("breaks_width", c(w, o, length(x), x), breaks_width(w, o)(x))

tr <- list(list(0, transform_asn(), 0, 0, 0, 0), list(1, transform_atanh(), 0, 0, 0, 0), list(2, transform_asinh(), 0, 0, 0, 0),
           list(3, transform_boxcox(0.5, 1), 0.5, 1, 0, 0), list(3, transform_boxcox(0, 0), 0, 0, 0, 0),
           list(3, transform_boxcox(-1, 0.5), -1, 0.5, 0, 0), list(4, transform_modulus(0.5, 1), 0.5, 1, 0, 0),
           list(4, transform_modulus(0, 2), 0, 2, 0, 0), list(5, transform_yj(0.5), 0.5, 0, 0, 0),
           list(5, transform_yj(0), 0, 0, 0, 0), list(5, transform_yj(2), 2, 0, 0, 0), list(5, transform_yj(1.7), 1.7, 0, 0, 0),
           list(6, transform_exp(exp(1)), 0, 0, 0, exp(1)), list(6, transform_exp(2), 0, 0, 0, 2),
           list(6, transform_exp(10), 0, 0, 0, 10), list(7, transform_identity(), 0, 0, 0, 0),
           list(8, transform_log(exp(1)), 0, 0, 0, exp(1)), list(8, transform_log10(), 0, 0, 0, 10),
           list(8, transform_log2(), 0, 0, 0, 2), list(9, transform_log1p(), 0, 0, 0, 0),
           list(10, transform_pseudo_log(), 0, 0, 1, exp(1)), list(10, transform_pseudo_log(0.5, 10), 0, 0, 0.5, 10),
           list(11, transform_logit(), 0, 0, 0, 0), list(12, transform_probit(), 0, 0, 0, 0),
           list(13, transform_reciprocal(), 0, 0, 0, 0), list(14, transform_reverse(), 0, 0, 0, 0),
           list(15, transform_sqrt(), 0, 0, 0, 0))
grid <- c(-12.5, -3, -1, -0.5, -0.1, -1e-5, 0, 1e-5, 0.001, 0.1, 0.25, 0.5, 0.75, 0.9, 1, 1.5, 2, 3.7, 10, 55, 1000, 1e6)
for (t in tr) {
  for (x in grid) for (mode in 0:3) {
    f <- list(t[[2]]$transform, t[[2]]$inverse, t[[2]]$d_transform, t[[2]]$d_inverse)[[mode + 1]]
    want <- tryCatch(suppressWarnings(f(x)), error = function(e) NULL)
    if (!is.null(want) && length(want) == 1)
      add("transform", c(t[[1]], t[[3]], t[[4]], t[[5]], t[[6]], mode, x), want)
  }
}

xv <- c(-2, 0, 0.3, 1, 2.5, 7, 10, 123, Inf, -Inf)
for (x in xv) for (rg in list(list(c(0, 1), c(0, 10)), list(c(-1, 1), c(2, 8)), list(c(5, 5), c(0, 1)), list(c(0, 1), c(3, 3)))) {
  add("rescale", c(x, rg[[1]], rg[[2]]), rescale(x, rg[[1]], rg[[2]]))
  add("rescale_mid", c(x, rg[[1]], rg[[2]], 3), rescale_mid(x, rg[[1]], rg[[2]], 3))
}
for (x in xv) {
  add("rescale_max", c(x, 1, 10), rescale_max(x, c(0, 1), c(0, 10)))
  rules <- list(oob_censor, oob_censor_any, oob_squish, oob_squish_any, oob_squish_infinite, oob_keep)
  for (k in seq_along(rules)) add("oob", c(x, 0, 5, k - 1), rules[[k]](x, c(0, 5)))
}
for (r in list(c(1, 5), c(3, 3), c(0, 0), c(-2, 8))) for (mul in c(0, 0.05)) for (ad in c(0, 1)) {
  e <- expand_range(r, mul, ad, 2)
  add("expand_range", c(r, mul, ad, 2, 0), e[1]); add("expand_range", c(r, mul, ad, 2, 1), e[2])
}
for (r in list(c(1, 1), c(1, 1 + 1e-14), c(1, 1.001), c(0, 1e-20), c(-1, 1), c(5, Inf), c(0, 0)))
  add("zero_range", r, as.numeric(zero_range(r)))
emit("scale", c("labeling", "scales"), list(cases))
