# Writes the colour-vision-deficiency matrices of colorspace as Neper source (lib/e/gfx/cvd_table.e).
library(colorspace)
ns <- asNamespace("colorspace")
cat("// generated from colorspace by scripts/gen_cvd_table.R: the 11 severity matrices of each anomaly, row-wise\n")
for (nm in c("deutanomaly_cvd", "protanomaly_cvd", "tritanomaly_cvd")) {
  m <- ns[[nm]]; v <- unlist(lapply(m, function(z) as.vector(t(z))))
  cat("\nfn ", sub("anomaly_cvd", "", nm), "_table() -> [99]f64 {\n    var t: [99]f64 = zero\n", sep = "")
  for (i in seq_along(v)) cat(sprintf("    t[%dusize] = %s%.22ff64\n", i - 1, if (v[i] < 0) "0.0f64 - " else "", abs(v[i])))
  cat("    ret t\n}\n")
}
