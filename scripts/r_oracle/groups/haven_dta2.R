# haven read_dta on the second set of Stata files (scripts/make_haven_dta2.R): haven-written formats 113 to 119
# with tagged missing values, labelled columns with tagged labels, UTF-8 and strLs, and hand-built formats 104 to 116
# (both byte orders) with every storage type.
#   args: (file index, column 0-based or -1 for the dataset, stat); files: w8 w10 w12 w13 w14 w15, then h<fmt>L and h<fmt>M for
#   fmt in 104 105 108 110 111 112 113 114 115 116, then d8 d14 d15 (date and time columns, scripts/make_haven_dta_dates.R; the numeric stats are of the R value, so %td, %d, %tc and %tC are converted)
#   fn "dta2": stat 0 name strsum 1 variable-label strsum 2 numeric sum 3 numeric position-weighted sum 4 NA count 5 text position-weighted strsum
#   6 number of value labels 7 sum of the value-label codes that are not missing 8 position-weighted label-text strsums
#   9 sum over the rows of position * na_tag byte (0 for a plain NA) 10 the same over the value-label codes 11 format.stata strsum 12 total bytes of a text column
#   dataset (column -1): 0 nvars 1 nobs 2 label strsum
suppressMessages(library(haven))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("dta2", args, want, rel = 1e-12, abs = 1e-12)
ss <- function(s) { if (is.null(s) || length(s) == 0 || is.na(s)) return(0); b <- as.integer(charToRaw(s)); if (!length(b)) 0 else sum(as.numeric(seq_along(b)) * b) }
tagsum <- function(xv) { tg <- na_tag(xv); tv <- ifelse(is.na(tg), 0, as.numeric(sapply(ifelse(is.na(tg), "\001", tg), function(s) as.integer(charToRaw(s))[1]))); sum(as.numeric(seq_along(tv)) * tv) }
fmts <- c(104, 105, 108, 110, 111, 112, 113, 114, 115, 116)
files <- c(sprintf("w%d.dta", c(8, 10, 12, 13, 14, 15)), as.vector(rbind(sprintf("h%dL.dta", fmts), sprintf("h%dM.dta", fmts))), sprintf("d%d.dta", c(8, 14, 15)))
for (f in seq_along(files)) {
  d <- read_dta(file.path(root, "tests", "data", "haven", files[f]))
  add(c(f, -1, 0), ncol(d)); add(c(f, -1, 1), nrow(d)); add(c(f, -1, 2), ss(attr(d, "label")))
  for (j in seq_along(d)) {
    x <- d[[j]]
    add(c(f, j - 1, 0), ss(names(d)[j])); add(c(f, j - 1, 1), ss(attr(x, "label"))); add(c(f, j - 1, 11), ss(attr(x, "format.stata")))
    if (is.character(x)) {
      add(c(f, j - 1, 5), sum(seq_along(x) * sapply(x, ss))); add(c(f, j - 1, 12), sum(nchar(x, type = "bytes"), na.rm = TRUE))
    } else {
      xv <- as.numeric(unclass(x)); ok <- !is.na(xv)
      add(c(f, j - 1, 2), sum(xv[ok])); add(c(f, j - 1, 3), sum(seq_along(xv)[ok] * xv[ok])); add(c(f, j - 1, 4), sum(!ok))
      add(c(f, j - 1, 9), tagsum(xv))
    }
    lb <- attr(x, "labels")
    add(c(f, j - 1, 6), length(lb))
    if (length(lb)) {
      lv <- as.numeric(lb)
      add(c(f, j - 1, 7), sum(lv[!is.na(lv)])); add(c(f, j - 1, 8), sum(seq_along(lb) * sapply(names(lb), ss))); add(c(f, j - 1, 10), tagsum(lv))
    }
  }
}
emit("haven_dta2", "haven", list(cases))
