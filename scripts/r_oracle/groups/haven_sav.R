# haven read_sav on tests/data/haven/s1.sav (uncompressed), s2.sav (bytecode) and s3.zsav (zlib), written by scripts/make_haven_sav.R.
#   args: (file 1 to 3, column 0-based or -1 for the dataset, stat)
#   fn "sav": stat 0 name strsum  1 variable-label strsum  2 numeric sum  3 numeric position-weighted sum  4 NA count (user_na = TRUE)
#   5 text position-weighted strsum  6 number of value labels  7 sum of numeric label codes (text codes: position-weighted strsum)
#   8 position-weighted strsum of the label names  9 format.spss strsum  10 display_width (8 when absent)  11 number of na_values
#   12 sum of na_values (text: strsum)  13 na_range low  14 na_range high  15 NA count with user_na = FALSE  16 total characters of a text column
#   dataset (column -1): 0 nvars 1 nobs
suppressMessages(library(haven))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("sav", args, want, rel = 1e-12, abs = 1e-12)
ss <- function(s) { if (is.null(s) || length(s) == 0 || is.na(s)) return(0); b <- as.integer(charToRaw(s)); if (!length(b)) 0 else sum(as.numeric(seq_along(b)) * b) }
files <- c("s1.sav", "s2.sav", "s3.zsav")
for (f in seq_along(files)) {
  path <- file.path(root, "tests", "data", "haven", files[f])
  d <- read_sav(path, user_na = TRUE)
  dn <- read_sav(path, user_na = FALSE)
  add(c(f, -1, 0), ncol(d)); add(c(f, -1, 1), nrow(d))
  for (j in seq_along(d)) {
    x <- d[[j]]; xn <- dn[[j]]
    add(c(f, j - 1, 0), ss(names(d)[j])); add(c(f, j - 1, 1), ss(attr(x, "label")))
    fm <- attr(x, "format.spss"); add(c(f, j - 1, 9), ss(fm))
    dw <- attr(x, "display_width"); add(c(f, j - 1, 10), if (is.null(dw)) 8 else dw)
    if (typeof(x) == "character") {
      add(c(f, j - 1, 5), sum(as.numeric(seq_along(x)) * sapply(as.character(unclass(x)), ss)))
      add(c(f, j - 1, 16), sum(nchar(x, type = "bytes")))
      add(c(f, j - 1, 15), sum(is.na(unclass(xn))))
      nv <- attr(x, "na_values"); add(c(f, j - 1, 11), length(nv))
      if (length(nv)) add(c(f, j - 1, 12), sum(as.numeric(seq_along(nv)) * sapply(nv, ss)))
    } else {
      xv <- as.numeric(unclass(x)); ok <- !is.na(xv)
      add(c(f, j - 1, 2), sum(xv[ok])); add(c(f, j - 1, 3), sum(seq_along(xv)[ok] * xv[ok])); add(c(f, j - 1, 4), sum(!ok))
      add(c(f, j - 1, 15), sum(is.na(as.numeric(unclass(xn)))))
      nv <- attr(x, "na_values"); add(c(f, j - 1, 11), length(nv))
      if (length(nv)) add(c(f, j - 1, 12), sum(nv))
      nr <- attr(x, "na_range")
      if (length(nr)) { add(c(f, j - 1, 13), nr[1]); add(c(f, j - 1, 14), nr[2]) }
    }
    lb <- attr(x, "labels")
    add(c(f, j - 1, 6), length(lb))
    if (length(lb)) {
      add(c(f, j - 1, 7), if (is.character(lb)) sum(as.numeric(seq_along(lb)) * sapply(unname(lb), ss)) else sum(lb))
      add(c(f, j - 1, 8), sum(as.numeric(seq_along(lb)) * sapply(names(lb), ss)))
    }
  }
}
emit("haven_sav", "haven", list(cases))
