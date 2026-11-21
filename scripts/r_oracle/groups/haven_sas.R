# haven read_sas on iris, datetime, hadley and tagged-na .sas7bdat (copied from haven), hadley and tagged-na with their sas7bcat
# catalogs (real SAS files), and rle64, rle32 and raw64 (written by ReadStat through scripts/make_haven_sas2.c: row-compressed 64 and
# 32 bit, uncompressed 64 bit), and rdc32, rdc64 (RDC, SASYZCR2), rle32be, rdc64be, raw64be (big-endian) rewritten from those by scripts/make_haven_sas3.py.
#   args: (file 1..12, column 0-based or -1 for the dataset, stat)
#   fn "sas": stat 0 name strsum  1 variable-label strsum  2 numeric sum  3 numeric position-weighted sum  4 NA count
#   5 text position-weighted strsum  6 format.sas strsum  7 sum over the rows of position * na_tag byte (0 for a plain NA)  8 total bytes of a text column
#   9 number of value labels  10 sum of numeric label codes (text codes: position-weighted strsum)  11 position-weighted strsum of the label names
#   12 sum over the labels of position * na_tag byte
#   dataset (column -1): 0 nvars 1 nobs
suppressMessages(library(haven))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("sas", args, want, rel = 1e-12, abs = 1e-12)
ss <- function(s) { if (is.null(s) || length(s) == 0 || is.na(s)) return(0); b <- as.integer(charToRaw(s)); if (!length(b)) 0 else sum(as.numeric(seq_along(b)) * b) }
files <- c("iris.sas7bdat", "datetime.sas7bdat", "hadley.sas7bdat", "tagged-na.sas7bdat", "rle64.sas7bdat", "rle32.sas7bdat", "raw64.sas7bdat", "rdc32.sas7bdat", "rdc64.sas7bdat", "rle32be.sas7bdat", "rdc64be.sas7bdat", "raw64be.sas7bdat")
cats <- c(NA, NA, "formats.sas7bcat", "tagged-na.sas7bcat", rep(NA, 8))
for (f in seq_along(files)) {
  cf <- if (is.na(cats[f])) NULL else file.path(root, "tests", "data", "haven", cats[f])
  d <- read_sas(file.path(root, "tests", "data", "haven", files[f]), catalog_file = cf)
  add(c(f, -1, 0), ncol(d)); add(c(f, -1, 1), nrow(d))
  for (j in seq_along(d)) {
    x <- d[[j]]
    add(c(f, j - 1, 0), ss(names(d)[j])); add(c(f, j - 1, 1), ss(attr(x, "label", exact = TRUE))); add(c(f, j - 1, 6), ss(attr(x, "format.sas")))
    if (typeof(x) == "character") {
      add(c(f, j - 1, 5), sum(as.numeric(seq_along(x)) * sapply(as.vector(unclass(x)), ss))); add(c(f, j - 1, 8), sum(nchar(as.vector(unclass(x)), type = "bytes")))
    } else {
      xv <- as.numeric(unclass(x)); ok <- !is.na(xv)
      add(c(f, j - 1, 2), sum(xv[ok])); add(c(f, j - 1, 3), sum(seq_along(xv)[ok] * xv[ok])); add(c(f, j - 1, 4), sum(!ok))
      tg <- na_tag(xv); tv <- ifelse(is.na(tg), 0, as.numeric(sapply(ifelse(is.na(tg), "\001", tg), function(s) as.integer(charToRaw(s))[1])))
      add(c(f, j - 1, 7), sum(as.numeric(seq_along(tv)) * tv))
    }
    lb <- attr(x, "labels")
    add(c(f, j - 1, 9), length(lb))
    if (length(lb)) {
      if (is.character(lb)) {
        add(c(f, j - 1, 10), sum(as.numeric(seq_along(lb)) * sapply(unname(lb), ss)))
        add(c(f, j - 1, 12), 0)
      } else {
        lv <- as.numeric(unclass(lb)); add(c(f, j - 1, 10), sum(lv[!is.na(lv)]))
        lt <- na_tag(lv); ltv <- ifelse(is.na(lt), 0, as.numeric(sapply(ifelse(is.na(lt), "\001", lt), function(s) as.integer(charToRaw(s))[1])))
        add(c(f, j - 1, 12), sum(as.numeric(seq_along(ltv)) * ltv))
      }
      add(c(f, j - 1, 11), sum(as.numeric(seq_along(lb)) * sapply(names(lb), ss)))
    }
  }
}
emit("haven_sas", "haven", list(cases))
