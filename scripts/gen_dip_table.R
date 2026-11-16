# writes lib/e/algo/stat/dip_table.e: the diptest::qDiptab quantile table (21 sample sizes by 26 probabilities), row-wise
.libPaths(c(Sys.getenv("R_ORACLE_LIB"), .libPaths())); suppressMessages(library(diptest)); data(qDiptab)
out <- c("// generated from diptest by scripts/gen_dip_table.R: qDiptab, 21 sample sizes by 26 probabilities, row-wise", "",
         "fn dip_table() -> [546]f64 {", "    var t: [546]f64 = zero")
k <- 0
for (i in 1:21) for (j in 1:26) { out <- c(out, sprintf("    t[%dusize] = %sf64", k, formatC(qDiptab[i, j], digits = 17, format = "g", flag = "#"))); k <- k + 1 }
out <- c(out, "    ret t", "}", "",
  sprintf("fn dip_sizes() -> [21]f64 {\n    var t: [21]f64 = zero\n%s\n    ret t\n}", paste(sprintf("    t[%dusize] = %sf64", 0:20, format(as.numeric(dimnames(qDiptab)$n), nsmall = 1)), collapse = "\n")),
  "", sprintf("fn dip_probs() -> [26]f64 {\n    var t: [26]f64 = zero\n%s\n    ret t\n}", paste(sprintf("    t[%dusize] = %sf64", 0:25, formatC(as.numeric(dimnames(qDiptab)$Pr), digits = 17, format = "g", flag = "#")), collapse = "\n")))
writeLines(out, "lib/e/algo/stat/dip_table.e")
