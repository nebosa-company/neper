# Writes the SPSS test files of tests/data/haven (s1.sav plain, s2.sav bytecode, s3.zsav zlib, s4.sav ascii mix) with haven 2.5.
suppressMessages(library(haven))
set.seed(7); n <- 300
lng <- function(k, w) vapply(seq_len(k), function(i) paste(rep(letters[(i %% 26) + 1], w + (i %% 7) - 3), collapse = ""), "")
df <- data.frame(id = 1:n, xnorm = round(rnorm(n), 4), small = as.integer(sample(c(-3:20, NA), n, TRUE)), zero = 0, stringsAsFactors = FALSE)
df$yval <- c(NA, round(runif(n - 1) * 100))
df$ints <- as.numeric(sample(c(-99:150, NA), n, TRUE))
df$s10 <- c("a", "bb", "", "dddd", rep(c("txt with spaces", "café ü", "x"), length.out = n - 4))
df$s300 <- lng(n, 300)
df$s1000 <- lng(n, 1000)
df$s70 <- lng(n, 70)
df$lev <- labelled(sample(1:3, n, TRUE), labels = c(low = 1, mid = 2, high = 3), label = "Level")
df$chrlab <- labelled(sample(c("a", "b", "c"), n, TRUE), labels = c(Alpha = "a", Beta = "b"), label = "Chr labelled")
df$um <- labelled_spss(sample(c(1:4, 99), n, TRUE), labels = c(yes = 1, no = 2, dk = 99), na_values = c(99), label = "User missing")
df$ur <- labelled_spss(sample(c(1:9, 98, 99), n, TRUE), labels = c(lo = 1, hi = 9), na_range = c(90, 100), na_values = c(5), label = "User range")
df$ucm <- labelled_spss(sample(c("a", "b", "none"), n, TRUE), na_values = c("none"), label = "Chr user missing")
df$d <- as.Date("2020-01-15") + sample(0:2000, n, TRUE)
df$dt <- as.POSIXct("2021-03-04 05:06:07", tz = "UTC") + sample(0:100000, n, TRUE)
df$tm <- hms::as_hms(sample(0:86399, n, TRUE))
df$flag <- sample(c(TRUE, FALSE, NA), n, TRUE)
df$a_rather_long_variable_name_here <- round(runif(n), 6)
attr(df$xnorm, "label") <- "A normal"
attr(df$yval, "format.spss") <- "F8.2"
attr(df$yval, "display_width") <- 12L
attr(df$s10, "format.spss") <- "A10"
attr(df$ints, "format.spss") <- "COMMA10.1"
write_sav(df, "tests/data/haven/s1.sav", compress = "none")
write_sav(df, "tests/data/haven/s2.sav", compress = "byte")
write_sav(df, "tests/data/haven/s3.zsav", compress = "zsav")
