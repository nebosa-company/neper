# colorspace: lighten and darken (HCL, HLS, combined), polarLAB and polarLUV coordinates, hex of polarLAB, APCA contrast.
#   fn "lighten": (rgb, amount, method 0 relative 1 absolute, space 0 HCL 1 HLS 2 combined, fixup, dark 0/1) -> packed hex or -1
#   fn "coords": (rgb, kind 0 polarLAB 1 polarLUV, q 0 L 1 C 2 H) -> the coordinate;  fn "labhex": (L, C, H, fixup) -> packed hex or -1
#   fn "apca": (rgb1, rgb2, reverse 0/1) -> the ratio
suppressMessages(library(colorspace))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
pk <- function(h) { if (is.na(h)) return(-1); v <- col2rgb(h); v[1] * 65536 + v[2] * 256 + v[3] }
set.seed(20261117)
hexs <- c(sprintf("#%02X%02X%02X", sample(0:255, 60, TRUE), sample(0:255, 60, TRUE), sample(0:255, 60, TRUE)), "#000000", "#FFFFFF", "#FF0000", "#00FF00", "#0000FF", "#808080", "#FFFF00", "#00FFFF", "#FF00FF")
for (h in hexs) {
  for (am in c(-0.7, -0.25, 0.1, 0.3, 0.8)) for (me in 0:1) for (sp in 0:2) for (fx in c(TRUE, FALSE)) {
    r <- tryCatch(suppressWarnings(lighten(h, am, method = c("relative", "absolute")[me + 1], space = c("HCL", "HLS", "combined")[sp + 1], fixup = fx)), error = function(e) NA_character_)
    add("lighten", c(pk(h), am, me, sp, as.numeric(fx), 0), pk(r), 0, 0)
  }
  for (am in c(0.2, 0.5)) {
    r <- darken(h, am)
    add("lighten", c(pk(h), am, 0, 2, 1, 1), pk(r), 0, 0)
  }
  rgb <- col2rgb(h)[, 1] / 255
  for (k in 0:1) {
    co <- if (k == 0) as(sRGB(rgb[1], rgb[2], rgb[3]), "polarLAB")@coords else as(sRGB(rgb[1], rgb[2], rgb[3]), "polarLUV")@coords
    for (q in 0:2) add("coords", c(pk(h), k, q), co[1, q + 1], 1e-9, 1e-9)
  }
  j <- sample(length(hexs), 1)
  for (rv in 0:1) add("apca", c(pk(h), pk(hexs[j]), rv), contrast_ratio(h, hexs[j], algorithm = "APCA")[1, rv + 1], 1e-10, 1e-10)
}
for (rep in 1:300) {
  l <- runif(1, 0, 100); cc <- runif(1, 0, 130); hh <- runif(1, 0, 360); fx <- sample(c(TRUE, FALSE), 1)
  r <- tryCatch(hex(polarLAB(l, cc, hh), fixup = fx), error = function(e) NA_character_)
  add("labhex", c(l, cc, hh, as.numeric(fx)), pk(r), 0, 0)
}
emit("hclops", "colorspace", list(cases))
