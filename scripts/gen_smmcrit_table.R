# Generates lib/e/algo/stat/smmcrit_table.e: WRS2's studentised-maximum-modulus critical-value table (20 degrees of freedom by C = 2..28 contrasts, row-wise),
# read back through smmcrit at the table's own degrees of freedom. Run: Rscript scripts/gen_smmcrit_table.R
suppressMessages(library(WRS2))
nu <- c(2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 30, 40, 60, 200)
out <- c("// generated from WRS2 by scripts/gen_smmcrit_table.R: smmcrit's table, 20 degrees of freedom (2 3 4 5 6 7 8 9 10 11 12 14 16 18 20 24 30 40 60 200) by 27 contrast counts (C = 2..28), row-wise", "", "fn smmcrit_table() -> [540]f64 {", "    var t: [540]f64 = zero")
k <- 0
for (i in seq_along(nu)) for (cc in 2:28) {
  v <- format(WRS2:::smmcrit(nu[i], cc), digits = 17)
  if (!grepl("[.e]", v)) v <- paste0(v, ".0")
  out <- c(out, sprintf("    t[%dusize] = %sf64", k, v))
  k <- k + 1
}
out <- c(out, "    ret t", "}")
writeLines(out, "lib/e/algo/stat/smmcrit_table.e")
