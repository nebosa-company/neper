# Writes the Stata files with date and time columns of tests/data/haven (d8.dta format 113, d14.dta format 118, d15.dta format 119)
# with haven 2.5: Date (%td), POSIXct (%tc, milliseconds), and numeric columns carrying other Stata formats.
# Run from the repository root: Rscript scripts/make_haven_dta_dates.R tests/data/haven
suppressMessages(library(haven))
dir <- commandArgs(TRUE)[1]
d <- data.frame(id = 1:6)
d$day <- as.Date("2020-01-15") + c(0, 31, NA, 1000, -20000, 365.5)
d$when <- as.POSIXct("2021-03-04 05:06:07", tz = "UTC") + c(0, 3600.5, NA, 1e6, -5e8, 0.25)
d$leap <- c(1e12, 2e12, NA, 3.3e12, -1e12, 0)
attr(d$leap, "format.stata") <- "%tC"
d$monthly <- c(0, 12, 700, NA, -5, 3)
attr(d$monthly, "format.stata") <- "%tm"
d$shortd <- c(100, 200, NA, 18000, -3, 0)
attr(d$shortd, "format.stata") <- "%d"
for (v in c(8, 14, 15)) write_dta(d, file.path(dir, sprintf("d%d.dta", v)), version = v)
