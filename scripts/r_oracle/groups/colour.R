# farver: convert_colour between every pair of the 15 colour spaces, white-reference changes for the
# relative ones, and compare_colour with the five distances. A convert case is
# (from, to, white_from x y z, white_to x y z, v1..v4, element), the values already in `from`;
# a compare case is (space, method, lightness, chroma, white_from, white_to, a1..a4, b1..b4).
library(farver)
set.seed(20261115)
spaces <- c("cmy", "cmyk", "hsl", "hsb", "hsv", "lab", "hunterlab", "lch", "luv", "rgb", "xyz", "yxy", "hcl", "oklab", "oklch")
dims <- ifelse(spaces == "cmyk", 4, 3)
pad <- function(v) c(v, rep(0, 4 - length(v)))

rgbs <- rbind(c(0, 0, 0), c(255, 255, 255), c(255, 0, 0), c(0, 255, 0), c(0, 0, 255), c(128, 128, 128), c(255, 255, 0),
              c(12, 200, 90), c(250, 20, 130), c(33, 33, 34), c(200, 180, 5), c(90, 10, 240),
              matrix(sample(0:255, 3 * 16, replace = TRUE), ncol = 3))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-7)

w65 <- as_white_ref("D65")
white_pairs <- list(list(w65, w65))
relative <- c("lab", "hunterlab", "lch", "luv", "xyz", "hcl")
for (f in seq_along(spaces)) {
  from_vals <- convert_colour(rgbs, "rgb", spaces[f])
  for (t in seq_along(spaces)) {
    pairs <- white_pairs
    if (spaces[f] %in% relative && spaces[t] %in% relative)
      pairs <- c(pairs, list(list(as_white_ref("D50"), w65), list(w65, as_white_ref("F2")), list(as_white_ref("A"), as_white_ref("C"))))
    rows <- if (f == 10) seq_len(nrow(rgbs)) else 1:12
    for (wp in pairs) for (i in rows) {
      v <- from_vals[i, seq_len(dims[f])]
      if (spaces[f] == "yxy" && v[3] == 0) next   # 0/0 in the yxy to XYZ step: farver reads uninitialised memory
      out <- convert_colour(matrix(v, nrow = 1), spaces[f], spaces[t], wp[[1]], wp[[2]])
      for (e in seq_len(dims[t]))
        add("convert", c(f, t, wp[[1]], wp[[2]], pad(v), e - 1), out[1, e])
    }
  }
}
methods <- c("euclidean", "cie1976", "cie94", "cie2000", "cmc")
for (sp in c("rgb", "lab", "hsl", "luv")) {
  f <- match(sp, spaces)
  vals <- convert_colour(rgbs, "rgb", sp)
  for (m in seq_along(methods)) for (k in 1:60) {
    i <- sample(nrow(rgbs), 1); j <- sample(nrow(rgbs), 1)
    a <- vals[i, , drop = FALSE]; b <- vals[j, , drop = FALSE]
    for (lc in list(c(2, 1), c(1, 1))) {
      if (m < 5 && !identical(lc, c(2, 1))) next
      d <- compare_colour(a, b, sp, method = methods[m], lightness = lc[1], chroma = lc[2])
      add("compare", c(f, m, lc, w65, w65, pad(a[1, ]), pad(b[1, ])), d[1, 1])
    }
  }
}
emit("colour", "farver", list(cases))
