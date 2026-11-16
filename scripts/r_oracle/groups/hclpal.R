# colorspace HCL palettes: every hcl_palettes() name with its own parameters, n colours each.
#   args: (type 0 sequential 1 diverging 2 qualitative, h1, h2, c1, c2, l1, l2, p1, p2, cmax, fixup, n, k)
#   contrast: (rgb1, rgb2) the WCAG ratio; cvd: (kind 0 deutan 1 protan 2 tritan, severity, rgb) the simulated rgb
#   NA parameters are NaN; the answer is r * 65536 + g * 256 + b, or -1 for NA
library(colorspace)
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("pal", args, want, rel = 0, abs = 0)
pk <- function(h) { if (is.na(h)) return(-1); v <- col2rgb(h); v[1] * 65536 + v[2] * 256 + v[3] }
pal <- hcl_palettes()
types <- c(Sequential = 0, Diverging = 1, Qualitative = 2)
for (i in seq_len(nrow(pal))) {
  ty <- types[[sub(" .*", "", as.character(pal$type[i]))]]
  pp <- as.numeric(unlist(pal[i, 2:11]))
  nm <- rownames(pal)[i]
  for (n in c(1, 2, 5, 9, 10)) for (fx in c(TRUE, FALSE)) {
    cols <- tryCatch(suppressWarnings(
      if (ty == 0) sequential_hcl(n, palette = nm, fixup = fx) else if (ty == 1) diverging_hcl(n, palette = nm, fixup = fx)
      else qualitative_hcl(n, palette = nm, fixup = fx)), error = function(e) NULL)
    if (is.null(cols)) next
    for (k in seq_len(n)) add(c(ty, pp[1:9], as.numeric(fx), n, k - 1), pk(cols[k]))
  }
}
addf <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-12, abs = 1e-12)
set.seed(20261115)
hexs <- c(sprintf("#%02X%02X%02X", sample(0:255, 40, TRUE), sample(0:255, 40, TRUE), sample(0:255, 40, TRUE)), "#000000", "#FFFFFF", "#FF0000", "#00FF00", "#0000FF", "#808080")
pk2 <- function(h) { v <- col2rgb(h); v[1] * 65536 + v[2] * 256 + v[3] }
for (i in seq_along(hexs)) {
  j <- (i * 7) %% length(hexs) + 1
  addf("contrast", c(pk2(hexs[i]), pk2(hexs[j])), contrast_ratio(hexs[i], hexs[j]))
  addf("contrast", c(pk2(hexs[i]), pk2("#FFFFFF")), contrast_ratio(hexs[i]))
  for (sev in c(0, 0.25, 0.5, 0.73, 1)) {
    addf("cvd", c(0, sev, pk2(hexs[i])), pk2(deutan(hexs[i], sev)))
    addf("cvd", c(1, sev, pk2(hexs[i])), pk2(protan(hexs[i], sev)))
    addf("cvd", c(2, sev, pk2(hexs[i])), pk2(tritan(hexs[i], sev)))
  }
}
emit("hclpal", "colorspace", list(cases))
