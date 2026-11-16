# haven read_dta on the files in tests/data/haven (written by scripts/make_haven_files.R), Stata formats 117 and 118.
#   args: (version file 13 14 15, column 0-based or -1 for the dataset, stat)
#   fn "dta": stat 0 name strsum 1 variable-label strsum 2 numeric sum 3 numeric position-weighted sum 4 NA count 5 text strsum (position-weighted over rows)
#   6 number of value labels 7 sum of value-label codes 8 sum of position-weighted label strsums;  dataset (column -1): 0 nvars 1 nobs 2 label strsum
suppressMessages(library(haven))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("dta", args, want, rel = 1e-12, abs = 1e-12)
ss <- function(s) { if (is.null(s) || is.na(s)) return(0); b <- utf8ToInt(s); if (!length(b)) 0 else sum(seq_along(b) * b) }
for (v in c(13, 14, 15)) {
  d <- read_dta(file.path(root, "tests", "data", "haven", sprintf("t%d.dta", v)))
  add(c(v, -1, 0), ncol(d)); add(c(v, -1, 1), nrow(d)); add(c(v, -1, 2), ss(attr(d, "label")))
  for (j in seq_along(d)) {
    x <- d[[j]]
    add(c(v, j - 1, 0), ss(names(d)[j])); add(c(v, j - 1, 1), ss(attr(x, "label")))
    if (is.character(x)) {
      add(c(v, j - 1, 5), sum(seq_along(x) * sapply(x, ss)))
    } else {
      xv <- as.numeric(unclass(x)); ok <- !is.na(xv)
      add(c(v, j - 1, 2), sum(xv[ok])); add(c(v, j - 1, 3), sum(seq_along(xv)[ok] * xv[ok])); add(c(v, j - 1, 4), sum(!ok))
    }
    lb <- attr(x, "labels")
    add(c(v, j - 1, 6), length(lb))
    if (length(lb)) { add(c(v, j - 1, 7), sum(lb)); add(c(v, j - 1, 8), sum(seq_along(lb) * sapply(names(lb), ss))) }
  }
}
emit("haven", "haven", list(cases))
