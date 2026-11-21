# Writes the SAS transport test files of tests/data/haven (x5.xpt version 5, x8.xpt version 8) with haven 2.5.
suppressMessages(library(haven))
set.seed(11); n <- 120
df <- data.frame(id = 1:n, xnorm = rnorm(n) * 10^sample(-8:8, n, TRUE), yval = round(runif(n) * 1000, 2), stringsAsFactors = FALSE)
df$big <- sample(c(1e30, -1e-30, 3.14159265358979, 0, 1, -1, 65535, 2^40, NA), n, TRUE)
df$s8 <- c("a", "bb", "", "dddd", rep(c("txt  with", "café", "x"), length.out = n - 4))
df$s200 <- vapply(seq_len(n), function(i) paste(rep(letters[(i %% 26) + 1], 1 + (i * 7) %% 200), collapse = ""), "")
tg <- sample(c("A", "B", "Z", "_", NA, NA), n, TRUE)
df$tagged <- ifelse(is.na(tg), 5, NA_real_)
df$d <- as.Date("2020-01-15") + sample(0:2000, n, TRUE)
df$dt <- as.POSIXct("2021-03-04 05:06:07", tz = "UTC") + sample(0:100000, n, TRUE)
df$tm <- hms::as_hms(sample(0:86399, n, TRUE))
df$a_rather_long_variable_name_here <- round(runif(n), 6)
attr(df$xnorm, "label") <- "A normal number"
attr(df$yval, "format.sas") <- "BEST12.3"
attr(df$d, "format.sas") <- "DATE9"
attr(df$dt, "format.sas") <- "DATETIME20"
attr(df$tm, "format.sas") <- "TIME8"
attr(df$s8, "label") <- "String label"
write_xpt(df, "tests/data/haven/x5.xpt", version = 5, name = "TESTDATA", label = "xport test")
df8 <- df; attr(df8$a_rather_long_variable_name_here, "label") <- "A long label for the long name"
write_xpt(df8, "tests/data/haven/x8.xpt", version = 8, name = "TESTDATA8")

# haven cannot write tagged missing values to xport: turn some of the plain missing cells of the column tagged into .A .B .Z ._ in the bytes
tag_cells <- function(path) {
  b <- readBin(path, "raw", file.size(path))
  at <- regexpr("HEADER RECORD*******OBS", rawToChar(replace(b, b == as.raw(0) | b > as.raw(127), as.raw(32))), fixed = TRUE, useBytes = TRUE)
  start <- at + 80 - 1
  w <- c(8, 8, 8, 8, max(nchar(df$s8, "bytes")), max(nchar(df$s200, "bytes")), 8, 8, 8, 8, 8)
  rl <- sum(w); off <- sum(w[1:6])
  for (i in seq_len(n)) if (!is.na(tg[i])) b[start + (i - 1) * rl + off + 1] <- charToRaw(tg[i])
  writeBin(b, path)
}
tag_cells("tests/data/haven/x5.xpt"); tag_cells("tests/data/haven/x8.xpt")
