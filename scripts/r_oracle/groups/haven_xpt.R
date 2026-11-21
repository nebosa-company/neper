# haven read_xpt on tests/data/haven/x5.xpt (version 5) and x8.xpt (version 8), written by scripts/make_haven_xpt.R.
#   args: (file 1 or 2, column 0-based or -1 for the dataset, stat)
#   fn "xpt": stat 0 name strsum  1 variable-label strsum  2 numeric sum  3 numeric position-weighted sum  4 NA count
#   5 text position-weighted strsum  6 format.sas strsum  7 sum over the rows of position * na_tag byte (0 for a plain NA)  8 total bytes of a text column
#   dataset (column -1): 0 nvars 1 nobs
suppressMessages(library(haven))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("xpt", args, want, rel = 1e-12, abs = 1e-12)
ss <- function(s) { if (is.null(s) || length(s) == 0 || is.na(s)) return(0); b <- as.integer(charToRaw(s)); if (!length(b)) 0 else sum(as.numeric(seq_along(b)) * b) }
files <- c("x5.xpt", "x8.xpt")
for (f in seq_along(files)) {
  d <- read_xpt(file.path(root, "tests", "data", "haven", files[f]))
  add(c(f, -1, 0), ncol(d)); add(c(f, -1, 1), nrow(d))
  for (j in seq_along(d)) {
    x <- d[[j]]
    add(c(f, j - 1, 0), ss(names(d)[j])); add(c(f, j - 1, 1), ss(attr(x, "label"))); add(c(f, j - 1, 6), ss(attr(x, "format.sas")))
    if (typeof(x) == "character") {
      add(c(f, j - 1, 5), sum(as.numeric(seq_along(x)) * sapply(x, ss))); add(c(f, j - 1, 8), sum(nchar(x, type = "bytes")))
    } else {
      xv <- as.numeric(unclass(x)); ok <- !is.na(xv)
      add(c(f, j - 1, 2), sum(xv[ok])); add(c(f, j - 1, 3), sum(seq_along(xv)[ok] * xv[ok])); add(c(f, j - 1, 4), sum(!ok))
      tg <- na_tag(xv); tv <- ifelse(is.na(tg), 0, as.numeric(sapply(ifelse(is.na(tg), "\001", tg), function(s) as.integer(charToRaw(s))[1])))
      add(c(f, j - 1, 7), sum(as.numeric(seq_along(tv)) * tv))
    }
  }
}
emit("haven_xpt", "haven", list(cases))
