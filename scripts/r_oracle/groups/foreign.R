# foreign: read.arff of dense ARFF files written by write.arff (numeric and nominal columns with missing values).
#   The files are written to tests/oracle/data/foreign_arff<i>.arff; args: (i, col)   fn "sum" (the sum of the numeric values or of the factor codes, NA removed)
#   "nas" (the number of missing values in the column) "dim" (col 0 the number of rows, col 1 the number of columns)
suppressMessages(library(foreign))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-12, abs = 1e-12)
# bytes are the same on every host: LF unless a file is built with its own line ends
writeLines <- function(text, con, ...) { if (is.character(con)) { con <- file(con, "wb"); on.exit(close(con)) }; base::writeLines(text, con, sep = "\n", useBytes = TRUE) }
set.seed(20261225)
root <- Sys.getenv("NEPER_ROOT", unset = getwd())
dir.create(file.path(root, "tests/oracle/data"), recursive = TRUE, showWarnings = FALSE)
# read.dbf beyond the values: "dname" (i, j) the position-weighted byte sum of field j's name, "dtype" the type letter's code (the data_types attribute), "dstr" the row- and position-weighted byte sum of
# a character field (as.is = TRUE), and for as.is = FALSE "dcode" (the position-weighted sum of a factor column's codes), "dnlev" and "dlev" (the sum over the levels of k * their byte sum). Levels sort in the C locale.
Sys.setlocale("LC_COLLATE", "C")
wsum <- function(s) { b <- as.numeric(charToRaw(s)); sum(seq_along(b) * b) }
dbfx <- function(i, p) {
  d <- suppressMessages(suppressWarnings(read.dbf(p, as.is = TRUE))); dt <- attr(d, "data_types")
  for (j in seq_along(d)) {
    add("dname", c(i, j - 1), wsum(names(d)[j])); add("dtype", c(i, j - 1), as.numeric(charToRaw(dt[j])))
    v <- d[[j]]
    if (is.character(v)) add("dstr", c(i, j - 1), sum(vapply(which(!is.na(v)), function(k) k * wsum(v[k]), 0)))
  }
  f <- suppressMessages(suppressWarnings(read.dbf(p)))
  for (j in seq_along(f)) if (is.factor(f[[j]])) {
    v <- f[[j]]; add("dcode", c(i, j - 1), sum(seq_along(v) * as.integer(v), na.rm = TRUE)); add("dnlev", c(i, j - 1), nlevels(v))
    add("dlev", c(i, j - 1), sum(vapply(seq_along(levels(v)), function(k) k * wsum(levels(v)[k]), 0)))
  }
}
for (i in 1:6) {
  n <- sample(8:40, 1)
  df <- data.frame(a = round(rnorm(n), 4), b = factor(sample(c("red", "green", "blue", "yellow"), n, replace = TRUE), levels = c("red", "green", "blue", "yellow")),
                   c = round(runif(n) * 100), d = factor(sample(c("yes", "no"), n, replace = TRUE)))
  df$a[sample(n, 2)] <- NA; df$b[sample(n, 2)] <- NA
  path <- file.path(root, sprintf("tests/oracle/data/foreign_arff%d.arff", i))
  write.arff(df, path)
  rd <- read.arff(path)
  add("dim", c(i, 0), nrow(rd)); add("dim", c(i, 1), ncol(rd))
  for (j in seq_along(rd)) {
    v <- rd[[j]]; add("sum", c(i, j - 1), if (is.factor(v)) sum(as.integer(v), na.rm = TRUE) else sum(v, na.rm = TRUE)); add("nas", c(i, j - 1), sum(is.na(v)))
  }
}
for (i in 1:6) {
  n <- sample(8:40, 1)
  df <- data.frame(a = round(rnorm(n) * 10, 3), k = sample(1:500, n, replace = TRUE), s = sample(c("alpha", "be", "gamma ray", "d"), n, replace = TRUE), l = sample(c(TRUE, FALSE), n, replace = TRUE), stringsAsFactors = FALSE)
  path <- file.path(root, sprintf("tests/oracle/data/foreign_dbf%d.dbf", i))
  write.dbf(df, path)
  rd <- read.dbf(path, as.is = TRUE); dbfx(i, path)
  add("ddim", c(i, 0), nrow(rd)); add("ddim", c(i, 1), ncol(rd))
  for (j in seq_along(rd)) {
    v <- rd[[j]]
    add("dsum", c(i, j - 1), if (is.character(v)) sum(nchar(trimws(v))) else sum(as.numeric(v), na.rm = TRUE)); add("dnas", c(i, j - 1), sum(is.na(v)))
  }
}
# ARFF date attributes: read.arff parses them with strptime in the local zone, so the zone is UTC here, and each is compared as seconds since 1970 (sum and missing count).
# R's strptime fills a month or day the format lacks from today, so a yyyy-DDD column depends on the date the oracle runs and is left out (a ceiling of the reader). The weekday ('D', %w) and week ('ww', %U) columns are read and ignored by both. Files 7 and 8 are a sparse file and a relational one, which read.arff refuses ("aerr" is 1 when read.arff errors, 0 when it reads); file 1 is dense and reads.
Sys.setenv(TZ = "UTC")
writeLines(c("@relation dates",
             "@attribute stamp date",
             "@attribute when date 'yyyy-MM-dd HH:mm:ss'",
             "@attribute short date 'dd/MM/yyyy HH:mm'",
             "@attribute day date 'yyyy-MM-dd'",
             "@attribute v numeric",
             "@attribute weekday date 'yyyy-MM-dd D'",
             "@attribute week date 'yyyy-MM-dd ww'",
             "@data",
             "2011-03-04 10:20:30,2011-03-04 10:20:30,04/03/2011 10:20,2011-03-04,1,2011-03-04 5,2011-03-04 3",
             "2011-03-04,1969-12-31 23:59:59,31/12/1969 23:59,1999-01-01,2,2011-03-04 1,2011-03-04 53",
             "2024-02-29 00:00:00,2024-02-29 00:00:00,29/02/2024 00:00,2024-02-29,3,2011-03-04 7,2011-03-04 54",
             "2011-02-30 10:20:30,2011-03-04 25:00:00,30/02/2011 10:20,2000-12-31,4,?,?",
             "?,?,?,?,5,2011-03-04 10,?",
             "2011-03-04 23:59:60,2024-02-29 12:00:00,01/01/2000 00:00,2001-07-15,6,?,2011-03-04 10"),
           file.path(root, "tests/oracle/data/foreign_arff9.arff"))
writeLines(c("@relation sparse", "@attribute a numeric", "@attribute b numeric", "@data", "{0 3}", "{1 4}"),
           file.path(root, "tests/oracle/data/foreign_arff7.arff"))
writeLines(c("@relation rel", "@attribute r relational", "@attribute x numeric", "@end r", "@data", "1"),
           file.path(root, "tests/oracle/data/foreign_arff8.arff"))
refused <- function(i) as.numeric(inherits(tryCatch(read.arff(file.path(root, sprintf("tests/oracle/data/foreign_arff%d.arff", i))), error = function(e) e), "error"))
for (i in c(1, 7, 8, 9)) add("aerr", c(i, 0), refused(i))
rd <- read.arff(file.path(root, "tests/oracle/data/foreign_arff9.arff"))
for (j in seq_along(rd)) {
  v <- rd[[j]]
  add("sum", c(9, j - 1), sum(as.numeric(v), na.rm = TRUE)); add("nas", c(9, j - 1), sum(is.na(v)))
}
# write.arff: "wr" args (i, ncols, nrows, kind[nc] (0 numeric 1 factor), nlev[nc], values[nr * nc] row-major, factor columns as 1-based codes, NaN for NA): 1 when the text Neper writes equals the file R wrote
for (i in 1:8) {
  n <- sample(6:30, 1); nc <- sample(2:4, 1); kinds <- sample(0:1, nc, replace = TRUE); nl <- ifelse(kinds == 1, sample(2:4, nc, replace = TRUE), 0)
  cols <- lapply(seq_len(nc), function(j) if (kinds[j] == 0) { v <- round(rnorm(n) * 10, 2); v[sample(n, 1)] <- NA; v } else { f <- sample(seq_len(nl[j]), n, replace = TRUE); f <- as.integer(f); f[sample(n, 1)] <- NA; f })
  df <- as.data.frame(lapply(seq_len(nc), function(j) if (kinds[j] == 0) cols[[j]] else factor(ifelse(is.na(cols[[j]]), NA, paste0("L", cols[[j]])), levels = paste0("L", seq_len(nl[j])))))
  names(df) <- paste0("V", seq_len(nc))
  path <- file.path(root, sprintf("tests/oracle/data/foreign_arffw%d.arff", i))
  write.arff(df, path, relation = "df")
  vals <- as.vector(t(sapply(seq_len(nc), function(j) as.numeric(cols[[j]]))))
  add("wr", c(i, nc, n, kinds, nl, vals), 1)
}
# write.arff on every column type (files foreign_arffv1 to 9): "wx" args (i, ncols, nrows, kind[nc] (0 numeric 1 factor 2 character 3 Date 4 POSIXct 5 logical 6 integer), nlev[nc], values row-major, NaN for NA;
# a factor or character column's value is the 1-based index into its levels or strings, whose texts are lvt[(l + j) %% 7 + 1] (l counted from 1, j the column from 1)), the relation and names from small tables of
# awkward ones: 1 when the bytes Neper writes equal the file R wrote.
lvt <- c("L1", "it's", "a\\b", "x y", "plain", "Z9", "q'r\\s"); nmtab <- c("V1", "2nd", "a b", "x.y", "_z", "Q"); reltab <- c("df", "my data", "1abc", "a-b")
pool <- c(100000, 1e15, 123456789012345, 0.0001, 1/3, 2^60, 1e-5, 1.5e-10, 12345678901234567, -0.5, 0.1 + 0.2, 1e5 + 0.5, 123456.7, 1e-300, 25, 0.00012345, 99999, -1e22, 1234567890123456, 5e-5)
wxcase <- function(i, stem, eol, fn) {
  nc <- if (i <= 3) 6 else sample(3:6, 1); n <- sample(5:14, 1)
  kinds <- if (i <= 3) sample(0:6, 6) else sample(0:6, nc, replace = TRUE)
  nl <- integer(nc); vals <- matrix(NA_real_, n, nc); cols <- list()
  for (j in seq_len(nc)) {
    k <- kinds[j]
    v <- switch(k + 1,
      { x <- c(sample(pool, min(n, 6)), round(rnorm(n) * 10^sample(-4:9, 1), sample(0:7, 1)))[seq_len(n)]; x },
      { nl[j] <- sample(2:4, 1); sample(seq_len(nl[j]), n, replace = TRUE) },
      { nl[j] <- n; seq_len(n) },
      sample(-800:40000, n, replace = TRUE),
      { d <- sample(0:30000, n, replace = TRUE) * 86400; m <- (i + j) %% 3; if (m == 1) d + 60 * sample(0:1439, n, replace = TRUE) else if (m == 2) d + sample(0:86399, n, replace = TRUE) else d },
      sample(0:1, n, replace = TRUE),
      sample(c(-5000:100, 99999, 100000, 1999999), n, replace = TRUE))
    v <- as.numeric(v)
    if (k != 1 || n > 3) v[sample(n, 1)] <- NA
    vals[, j] <- v
    txt <- function(l) lvt[(l + j) %% 7 + 1]
    cols[[j]] <- switch(k + 1, v,
      factor(ifelse(is.na(v), NA, vapply(ifelse(is.na(v), 1, v), txt, "")), levels = vapply(seq_len(nl[j]), txt, "")),
      ifelse(is.na(v), NA_character_, vapply(ifelse(is.na(v), 1, v), txt, "")),
      as.Date(v, origin = "1970-01-01"), as.POSIXct(v, origin = "1970-01-01", tz = "UTC"), as.logical(v), as.integer(v))
  }
  df <- data.frame(cols, check.names = FALSE, stringsAsFactors = FALSE); names(df) <- nmtab[(seq_len(nc) - 1) %% 6 + 1]
  write.arff(df, file.path(root, sprintf("tests/oracle/data/foreign_%s%d.arff", stem, i)), relation = reltab[i %% 4 + 1], eol = eol)
  add(fn, c(i, nc, n, kinds, nl, as.vector(t(vals))), 1)
}
for (i in 1:9) wxcase(i, "arffv", "\n", "wx")
# write.dbf: "wd" args (i, ncols, nrows, kind[nc] (0 double 1 integer 2 logical 3 character of that many a's, 4 date as yyyymmdd), values col-major, NaN for NA): 1 when the bytes Neper writes equal the file R wrote past the date bytes 1 to 3
for (i in 1:9) {
  n <- sample(4:25, 1); nc <- sample(3:6, 1); kinds <- sample(0:4, nc, replace = TRUE)
  cols <- lapply(seq_len(nc), function(j) { v <- switch(kinds[j] + 1, round(rnorm(n) * 10^sample(0:4, 1), sample(1:4, 1)), as.numeric(sample(-3000:99999, n, replace = TRUE)), as.numeric(sample(0:1, n, replace = TRUE)), as.numeric(sample(1:12, n, replace = TRUE)), as.numeric(format(as.Date("2000-01-01") + sample(0:9000, n, replace = TRUE), "%Y%m%d"))); if (runif(1) < 0.7) v[sample(n, 1)] <- NA; v })
  df <- as.data.frame(lapply(seq_len(nc), function(j) { v <- cols[[j]]; switch(kinds[j] + 1, v, as.integer(v), as.logical(v), ifelse(is.na(v), NA_character_, vapply(v, function(k) strrep("a", k), "")), as.Date(ifelse(is.na(v), NA, format(v, scientific = FALSE)), "%Y%m%d")) }), stringsAsFactors = FALSE)
  names(df) <- paste0("V", seq_len(nc))
  write.dbf(df, file.path(root, sprintf("tests/oracle/data/foreign_dbfw%d.dbf", i)))
  add("wd", c(i, nc, n, kinds, unlist(cols)), 1)
}
# read.dbf on hand-built tables (files foreign_dbf7 to 9): numeric fields read as R_atof reads them (prefix, "NA", no digits missing, an integer column truncated until a value outside the int range
# turns it double), blanks and NULs in text, memo (M) and unknown types read as text, dates (D) as days, logicals with '?' and unknown letters missing, and deleted records kept. Same "ddim"/"dsum"/"dnas".
mkdbf <- function(path, fields, recs, deleted = rep(FALSE, length(recs))) {
  nf <- length(fields); reclen <- 1 + sum(vapply(fields, function(f) f$len, 0))
  hdr <- raw(32 + 32 * nf + 1); hdr[1] <- as.raw(3)
  put <- function(at, v, n) for (k in seq_len(n)) { hdr[at + k] <<- as.raw(v %% 256); v <- v %/% 256 }
  put(4, length(recs), 4); put(8, 32 + 32 * nf + 1, 2); put(10, reclen, 2)
  for (i in seq_len(nf)) {
    d <- 32 + 32 * (i - 1); nm <- charToRaw(fields[[i]]$name)
    hdr[d + seq_along(nm)] <- nm; hdr[d + 12] <- charToRaw(fields[[i]]$type); hdr[d + 17] <- as.raw(fields[[i]]$len); hdr[d + 18] <- as.raw(fields[[i]]$dec)
  }
  hdr[length(hdr)] <- as.raw(13)
  body <- raw(0)
  for (r in seq_along(recs)) {
    body <- c(body, charToRaw(if (deleted[r]) "*" else " "))
    for (i in seq_len(nf)) {
      s <- sprintf(paste0("%-", fields[[i]]$len, "s"), recs[[r]][i]); rw <- charToRaw(s); rw[rw == charToRaw("~")] <- as.raw(0); body <- c(body, rw)
    }
  }
  writeBin(c(hdr, body, as.raw(26)), path)
}
fld <- function(name, type, len, dec = 0) list(name = name, type = type, len = len, dec = dec)
dbfcases <- function(i, df) {
  add("ddim", c(i, 0), nrow(df)); add("ddim", c(i, 1), ncol(df))
  for (j in seq_along(df)) {
    v <- df[[j]]
    add("dsum", c(i, j - 1), if (is.character(v)) sum(nchar(v[!is.na(v)], "bytes")) else sum(as.numeric(v), na.rm = TRUE)); add("dnas", c(i, j - 1), sum(is.na(v)))
  }
}
p7 <- file.path(root, "tests/oracle/data/foreign_dbf7.dbf")
mkdbf(p7, list(fld("I", "N", 10, 0), fld("F", "F", 12, 3), fld("N2", "N", 8, 2)),
      list(c("  12abc", "1.5e2", "3.25"), c("1.9", ".5", "-0.5"), c("-2.9", "5.", "x1"), c("", "+3", "  "), c("***", "1e", "***"), c("abc", "NA", "7"),
           c("NA", "-.25e1", "1e-3"), c(" 7", "12345.678", "9"), c("3000000000", "0.001", "8"), c("5.5", "1e3", "2"), c("2.7", "-4", "6")))
dbfcases(7, suppressWarnings(read.dbf(p7, as.is = TRUE))); dbfx(7, p7)
p8 <- file.path(root, "tests/oracle/data/foreign_dbf8.dbf")
mkdbf(p8, list(fld("C", "C", 10), fld("1M", "M", 10), fld("D", "D", 8), fld("L", "L", 1), fld("C", "G", 6), fld("if", "T", 8)),
      list(c("  ab cd  ", "0000000001", "20110304", "T", "abc", "1"), c("ab~cd", "", "00000000", "?", "", ""), c("", "0000000012", "", " ", "   ", "20110304"),
           c("x", "7", "20110230", "y", "g~h", "2"), c("   z", "  42", "2011034", "F", "ab", "3"), c("tail", "9", "19700101", "x", "w", "4"), c("a", "1", "20240229", "n", "v", "5"),
           c("b", "2", "19000101", "N", "u", "6")))
dbfcases(8, suppressWarnings(read.dbf(p8, as.is = TRUE))); dbfx(8, p8)
p9 <- file.path(root, "tests/oracle/data/foreign_dbf9.dbf")
mkdbf(p9, list(fld("A", "N", 5, 0), fld("B", "C", 4)), list(c("1", "aa"), c("2", "bb"), c("3", "c"), c("4", "dd")), deleted = c(FALSE, TRUE, TRUE, FALSE))
dbfcases(9, read.dbf(p9, as.is = TRUE)); dbfx(9, p9)
# read.mtp (files foreign_mtp1 to 9): a Minitab portable worksheet of columns, constants and matrices written here in the layout Minitab writes (80 columns and a dot, five 16-wide numbers a line).
#   "mn" (i, 0) the number of entries; "mname" (i, k) the position-weighted byte sum of entry k's name; "mdim" (i, k, 0 rows 1 columns); "msum" (i, k) the position-weighted sum of its values (column-major);
#   "merr" (i, 0) 1 when read.mtp fails. Files 7 to 9 are a bad signature, a non-numeric data type and a truncated entry; file 5 has CRLF line ends.
mtpline <- function(s) if (nchar(s) >= 80) s else sprintf("%-79s.", s)
mtpfile <- function(path, ents, crlf = FALSE, head = "Minitab Portable Worksheet P1.1             1994 522 Release 9.1") {
  ln <- c(mtpline(head))
  for (e in ents) {
    v <- as.numeric(e$v)
    ln <- c(ln, mtpline(sprintf("%%%7d%7d%7d%7d %-8s", e$type, e$cnum, length(v), e$dtype, e$name)))
    wide <- any(abs(v[v != 0]) >= 1e99 | abs(v[v != 0]) < 1e-99)   # a three-digit exponent leaves no blank between 16-wide numbers, so those are written with seven decimals
    tv <- if (!is.null(e$raw)) sprintf("%16s", e$raw) else if (wide) sprintf("%16s", sprintf("%.7E", v)) else sprintf("%16.9E", v)
    for (s in seq(1, max(length(v), 1), by = 5)) ln <- c(ln, mtpline(paste(tv[s:min(s + 4, length(v))], collapse = "")))
  }
  txt <- paste0(paste(ln, collapse = if (crlf) "\r\n" else "\n"), if (crlf) "\r\n" else "\n")
  writeBin(charToRaw(txt), path)
}
mtpcases <- function(i, path) {
  r <- tryCatch(read.mtp(path), error = function(e) NULL)
  add("merr", c(i, 0), as.numeric(is.null(r)))
  if (is.null(r)) return(invisible())
  add("mn", c(i, 0), length(r))
  for (k in seq_along(r)) {
    v <- r[[k]]; nm <- charToRaw(names(r)[k]); add("mname", c(i, k - 1), sum(seq_along(nm) * as.numeric(nm)))
    add("mdim", c(i, k - 1, 0), if (is.matrix(v)) nrow(v) else length(v)); add("mdim", c(i, k - 1, 1), if (is.matrix(v)) ncol(v) else 1)
    add("msum", c(i, k - 1), sum(seq_along(v) * as.vector(v)))
  }
}
for (i in 1:6) {
  ents <- list()
  for (k in 1:sample(2:4, 1)) {
    n <- sample(c(1, 3, 5, 6, 12, 26), 1); mat <- sample(c(TRUE, FALSE), 1)
    if (mat) { nc <- sample(2:3, 1); ents[[k]] <- list(type = 4, cnum = k, dtype = nc, name = paste0("M", k, sample(c("a", "xyz", "q "), 1)), v = round(rnorm(n * nc) * 10^sample(-2:5, 1), sample(0:6, 1))) }
    else ents[[k]] <- list(type = if (n == 1) 2 else 3, cnum = k, dtype = 0, name = paste0("C", k, sample(c("", "abcdef", "r s"), 1)), v = round(rnorm(n) * 10^sample(-3:6, 1), sample(0:8, 1)))
  }
  if (i == 2) ents[[1]]$v[1:min(2, length(ents[[1]]$v))] <- c(0, -123456.789)[1:min(2, length(ents[[1]]$v))]
  p <- file.path(root, sprintf("tests/oracle/data/foreign_mtp%d.mtp", i)); mtpfile(p, ents, crlf = i == 5); mtpcases(i, p)
}
p <- file.path(root, "tests/oracle/data/foreign_mtp7.mtp"); mtpfile(p, list(list(type = 3, cnum = 1, dtype = 0, name = "x", v = 1:3)), head = "Minitab Worksheet"); mtpcases(7, p)
p <- file.path(root, "tests/oracle/data/foreign_mtp8.mtp"); mtpfile(p, list(list(type = 3, cnum = 1, dtype = 1, name = "t", v = 1:3))); mtpcases(8, p)
p <- file.path(root, "tests/oracle/data/foreign_mtp9.mtp"); mtpfile(p, list(list(type = 3, cnum = 1, dtype = 0, name = "x", v = 1:12))); tx <- readBin(p, "raw", 5000); writeBin(tx[1:(length(tx) - 120)], p); mtpcases(9, p)
# Numbers beyond 1e306 or below 1e-306 (fprec's other branch, file 10) and hexadecimal numbers as %lg reads them (file 11):
p <- file.path(root, "tests/oracle/data/foreign_mtp10.mtp")
mtpfile(p, list(list(type = 3, cnum = 1, dtype = 0, name = "XT", v = c(1.234565e306, 9.87654321e-307, 1.5e306, -2.345675e-306, 7.7777775e305, 1.7e306, 1.00000049e-300, 5.5e-308, 3.4e-320, 123456.789, 2.5e-305, 8.88888888e305, 1e-306, 1e306, 9.999995e305)),
                 list(type = 2, cnum = 2, dtype = 0, name = "BIG", v = 1.7e308)))
mtpcases(10, p)
p <- file.path(root, "tests/oracle/data/foreign_mtp11.mtp")
mtpfile(p, list(list(type = 3, cnum = 1, dtype = 0, name = "HX", v = rep(0, 9), raw = c("0x1A", "0x1.8p3", "-0X10", "0x.8", "0xff", "0x1p-2", "0x1.fffffep127", "0x10p0", "0x123456789"))))
mtpcases(11, p)
# read.systat (files foreign_sys1 to 24): Systat files written here in the packet layout of R_systat.c (records of 128-byte packets between 0x81 marks, reals then strings, final 0x82) and the two files
# that ship with foreign (Iris.syd, HillRace.SYD). The data frame is compared by "sn" (i, 0 rows / 1 columns), "sname" (i, j) the position-weighted byte sum of column j's name, "sstr" (i, j) 1 for a
# character column, "snum" (i, j) the position-weighted sum of a numeric column (NA left out), "snas" (i, j) the NA count, "slen" the summed byte length of a character column and "shash" its
# row- and position-weighted byte sum, "serr" (i, 0) 1 when read.systat fails.
shortb <- function(x) writeBin(as.integer(x), raw(), size = 2)
sysfile <- function(path, labels, isstr, vals, ntype = 2, v3 = TRUE, endnulls = 0, mtype = 1, last = 0x82, cut = 0, cmt = c("note", "$comment")) {
  nv <- length(labels); tsz <- if (ntype == 1) 4 else 8
  hdr <- as.raw(c(0x4B, 0x06))
  if (v3) {
    hdr <- c(hdr, shortb(nv), shortb(0), shortb(0), as.raw(6))
    for (t in cmt) hdr <- c(hdr, as.raw(0x48), charToRaw(sprintf("%-72s", t)), as.raw(0x48))
    hdr <- c(hdr, as.raw(6), shortb(nv), shortb(mtype), shortb(ntype), as.raw(6))
  } else hdr <- c(hdr, shortb(nv), shortb(mtype), shortb(ntype), as.raw(6))
  for (l in labels) hdr <- c(hdr, as.raw(12), charToRaw(sprintf("%-12s", l)), as.raw(12))
  nobs <- if (nv) length(vals[[1]]) else 0
  body <- raw(0)
  for (r in seq_len(nobs)) {
    pay <- raw(0)
    for (j in which(!isstr)) pay <- c(pay, writeBin(as.numeric(vals[[j]][r]), raw(), size = tsz))
    for (j in which(isstr)) pay <- c(pay, charToRaw(sprintf("%-12s", vals[[j]][r])))
    L <- length(pay); at <- 0
    while (L - at > 128) { body <- c(body, as.raw(0x81), pay[at + 1:128], as.raw(0x81)); at <- at + 128 }
    body <- c(body, as.raw(L - at), pay[at + seq_len(L - at)], as.raw(L - at))
  }
  out <- c(hdr, body, as.raw(last), raw(endnulls))
  if (cut > 0) out <- out[seq_len(length(out) - cut)]
  writeBin(out, path)
}
syscases <- function(i, path, raw = FALSE) {
  ex <- if (raw) 1 else numeric(0)   # a third argument of 1: to.data.frame = FALSE, the list the C reader makes
  r <- tryCatch(suppressWarnings(read.systat(path, to.data.frame = !raw)), error = function(e) NULL)
  add("serr", c(i, 0, ex), as.numeric(is.null(r)))
  if (is.null(r)) return(invisible())
  add("sn", c(i, 0, ex), if (raw) (if (length(r)) length(r[[1]]) else 0) else nrow(r)); add("sn", c(i, 1, ex), if (raw) length(r) else ncol(r))
  for (j in seq_along(r)) {
    v <- r[[j]]; nm <- charToRaw(names(r)[j]); add("sname", c(i, j - 1, ex), sum(seq_along(nm) * as.numeric(nm)))
    add("sstr", c(i, j - 1, ex), as.numeric(is.character(v))); add("snas", c(i, j - 1, ex), sum(is.na(v)))
    if (is.character(v)) {
      add("slen", c(i, j - 1, ex), sum(nchar(v[!is.na(v)], "bytes")))
      add("shash", c(i, j - 1, ex), sum(vapply(which(!is.na(v)), function(k) k * sum(seq_len(nchar(v[k], "bytes")) * as.numeric(charToRaw(v[k]))), 0)))
    } else add("snum", c(i, j - 1, ex), sum(seq_along(v) * v, na.rm = TRUE))
  }
}
sysdir <- file.path(root, "tests/oracle/data")
for (f in c("Iris.syd", "HillRace.SYD")) file.copy(system.file("files", f, package = "foreign"), file.path(sysdir, paste0("foreign_", tolower(f))), overwrite = TRUE)
syscases(1, file.path(sysdir, "foreign_iris.syd")); syscases(2, file.path(sysdir, "foreign_hillrace.syd"))
for (i in 3:16) {
  nd <- if (i == 3) 3 else sample(c(0, 1, 5, 12, 14, 15, 16, 17, 20, 31, 33), 1); nk <- if (i == 3) 2 else sample(c(0, 1, 2, 3, 5), 1)
  if (nd + nk == 0) nk <- 1
  n <- sample(1:9, 1); ntype <- if (i %% 3 == 0) 1 else 2
  labels <- c(if (nd) sprintf("V%02d", seq_len(nd)), if (nk) sprintf("%-8s$", paste0("S", seq_len(nk))))
  isstr <- c(rep(FALSE, nd), rep(TRUE, nk))
  vals <- c(lapply(seq_len(nd), function(j) { v <- round(rnorm(n) * 100, 3); if (n > 2 && sample(0:2, 1) == 0) v[sample(n, 1)] <- -1e36; v }),
            lapply(seq_len(nk), function(j) sample(c("alpha", "b", "gamma ray", "", "            ", "twelve_chars"), n, replace = TRUE)))
  if (nd == 0 || nk == 0) { }
  p <- file.path(sysdir, sprintf("foreign_sys%d.sys", i))
  sysfile(p, labels, isstr, vals, ntype = ntype, v3 = i %% 2 == 1, endnulls = if (i %% 4 == 0) 7 else 0, cmt = if (i %% 5 == 0) c("a", "b", "$c") else c("$only"))
  syscases(i, p)
}
# names: make.names and make.unique (a digit start, a reserved word, an invalid character, duplicates, a string name with its dollar)
p <- file.path(sysdir, "foreign_sys17.sys")
sysfile(p, c("1ST", "if", "A-B", "X", "X", "NAME$", ".5", "TRUE"), c(FALSE, FALSE, FALSE, FALSE, FALSE, TRUE, FALSE, FALSE),
        list(1:3, 4:6, 7:9, 1.5, 2.5, c("a", "b", "c"), 3:1, 6:4)[c(1, 2, 3, 4, 5, 6, 7, 8)] |> lapply(function(v) if (length(v) == 1) rep(v, 3) else v))
syscases(17, p)
# errors: not Systat, not rectangular (mtype 2), a missing final 0x82, a truncated file, a file with a record count that is not whole, a non-$ comment line run into the data
sysfile(file.path(sysdir, "foreign_sys18.sys"), c("A", "B"), c(FALSE, FALSE), list(1:3, 4:6), mtype = 2); syscases(18, file.path(sysdir, "foreign_sys18.sys"))
sysfile(file.path(sysdir, "foreign_sys19.sys"), c("A", "B"), c(FALSE, FALSE), list(1:3, 4:6), last = 0x83); syscases(19, file.path(sysdir, "foreign_sys19.sys"))
sysfile(file.path(sysdir, "foreign_sys20.sys"), c("A", "B"), c(FALSE, FALSE), list(1:3, 4:6), cut = 5); syscases(20, file.path(sysdir, "foreign_sys20.sys"))
sysfile(file.path(sysdir, "foreign_sys21.sys"), c("A", "S$"), c(FALSE, TRUE), list(1:3, c("a", "b", "c")), cut = 1); syscases(21, file.path(sysdir, "foreign_sys21.sys"))
writeBin(as.raw(c(1, 2, 3, 4, 5)), file.path(sysdir, "foreign_sys22.sys")); syscases(22, file.path(sysdir, "foreign_sys22.sys"))
sysfile(file.path(sysdir, "foreign_sys23.sys"), c("S$"), c(TRUE), list(c("a", "b")), v3 = FALSE); syscases(23, file.path(sysdir, "foreign_sys23.sys"))
sysfile(file.path(sysdir, "foreign_sys24.sys"), c("A", "B"), c(FALSE, FALSE), list(numeric(0), numeric(0))); syscases(24, file.path(sysdir, "foreign_sys24.sys"))
# read.arff on hand-written files (foreign_arffs1 to 9): quoting as scan reads it (a quote starts a quoted section anywhere in a text field, a doubled quote is one quote, a comma inside quotes stays), % comments, blank
# lines, CRLF, blanks inside numbers, "?" quoted or not, the levels of a factor being the values the data hold (sorted, in the C locale) with their backslashes removed, string columns, and the files read.arff refuses.
#   "aerr" (i, 0) 1 when read.arff fails; "rn" (i, 0 rows 1 columns); "rsum" (i, j) the position-weighted sum of a numeric, date or factor column's values (factor codes, seconds, NA left out); "rnas" the NA count;
#   "rnlev" the number of levels; "rlev" the sum over the levels (in order) of k * the position-weighted byte sum of the level; "rstr" the row-weighted position-weighted byte sum of a character column.
Sys.setlocale("LC_COLLATE", "C")
arffs <- list(
  c("@relation t", "@attribute f {a,b,c,zz}", "@attribute s string", "@attribute n numeric", "@attribute g {x,y}", "@data", "'b',\"x, y\",2,y", "?,'?',?,x", "c,'a\\\\b',3,x", "'',z,4,?", "b, spaced ,5,x",
    "b,'q''r',6,y", "B,Q,7,x", "a,'p\\q',8,'x\\y' % a comment", "% whole line", "", "a,\"dq\"\"z\",9,y", "zz,mid'dle q',10,x", "a,'',11,y"),
  c("@relation t", "@attribute f {a,b,c,zz}", "@attribute n numeric", "@data", "a,1", "b,2", "a,3"),
  c("@relation t", "@attribute n numeric", "@attribute m real", "@attribute k NUMERIC", "@data", " 1 2 ,.5,5.", "1e3,+5,-2.5E-2", "?,?,", "7,8,9", "007,1e+2,0.1"),
  c("@relation t", "@attribute n integer", "@data", "1"),
  c("@relation t", "@attribute n numeric", "@attribute m numeric", "@data", "Inf,-inf", "NaN,Infinity", "?,-Infinity", "1,0x1A"),
  c("@relation t", "@attribute a numeric", "@attribute b numeric", "@data", "1,2", "3"),
  c("@relation t", "@attribute a numeric", "@data", "abc"),
  c("@relation t", "@attribute a string", "@data", "'unterminated"),
  c("@relation t", "@attribute d date 'yyyy-MM-dd'", "@attribute e date", "@attribute s STRING", "@data", "'2011-03-04','2011-03-04 10:20:30',x", "?,'2011-03-04 25:00:00',?", "2011-02-30,2011-03-04 10:20:30,y"))
for (i in seq_along(arffs)) {
  p <- file.path(root, sprintf("tests/oracle/data/foreign_arffs%d.arff", i))
  txt <- paste0(paste(arffs[[i]], collapse = if (i == 3) "\r\n" else "\n"), if (i == 1) "" else if (i == 3) "\r\n" else "\n")
  writeBin(charToRaw(txt), p)
  d <- tryCatch(suppressWarnings(read.arff(p)), error = function(e) NULL)
  add("rerr", c(i, 0), as.numeric(is.null(d)))
  if (is.null(d)) next
  add("rn", c(i, 0), nrow(d)); add("rn", c(i, 1), ncol(d))
  for (j in seq_along(d)) {
    v <- d[[j]]; add("rnas", c(i, j - 1), sum(is.na(v)))
    if (is.factor(v)) {
      add("rsum", c(i, j - 1), sum(seq_along(v) * as.integer(v), na.rm = TRUE)); add("rnlev", c(i, j - 1), nlevels(v))
      add("rlev", c(i, j - 1), sum(vapply(seq_along(levels(v)), function(k) { b <- as.numeric(charToRaw(levels(v)[k])); k * sum(seq_along(b) * b) }, 0)))
    } else if (is.character(v)) {
      add("rstr", c(i, j - 1), sum(vapply(which(!is.na(v)), function(k) { b <- as.numeric(charToRaw(v[k])); k * sum(seq_along(b) * b) }, 0)))
    } else if (all(is.finite(as.numeric(v)[!is.na(v)]))) add("rsum", c(i, j - 1), sum(seq_along(v) * as.numeric(v), na.rm = TRUE))
  }
}
# Date columns whose format lacks a year, month or day (the YY column, %y, holds 68 and 69, the two sides of R's pivot; yyyy-DDD is %Y-%d%w with the month today's): R fills them from today, so only what does not depend on today is compared: "xtod" (seconds into the day), "xyr" (the year),
# "xmd" (month * 100 + day) and "xdom" (the day of the month), summed over the rows, and "xnas" (the missing count). args (1, col).
writeLines(c("@relation partial",
             "@attribute y date 'yyyy'",
             "@attribute t date 'HH:mm:ss'",
             "@attribute d date 'dd'",
             "@attribute ym date 'yyyy-MM'",
             "@attribute md date 'MM-dd'",
             "@attribute yy date 'YY'",
             "@attribute yd date 'yyyy-DDD'",
             "@attribute dd date 'DDD'",
             "@data",
             "2011,10:20:30,04,2011-03,03-04,99,2011-064,064",
             "1999,23:59:59,28,1999-12,12-25,05,1999-001,001",
             "?,00:00:00,15,?,?,?,?,?",
             "2030,25:00:00,01,2030-01,01-01,70,2011-123,123",
             "2000,00:00:00,01,2000-01,01-01,68,2012-366,366",
             "2000,00:00:00,01,2000-01,01-01,69,2011-021,021"),
           file.path(root, "tests/oracle/data/foreign_arffx1.arff"))
rd <- read.arff(file.path(root, "tests/oracle/data/foreign_arffx1.arff"))
want <- list(c("xtod", "xyr"), c("xtod"), c("xtod", "xdom"), character(0), c("xmd", "xtod"), c("xyr", "xtod"), c("xyr", "xdom", "xtod"), c("xdom"))
for (j in seq_along(rd)) {
  s <- as.numeric(rd[[j]]); ct <- as.POSIXct(s, origin = "1970-01-01", tz = "UTC")
  add("xnas", c(1, j - 1), sum(is.na(s)))
  # the whole value, R having filled what the format lacks from today (R takes it in local time): Neper is given that day
  add("xfull", c(1, j - 1, as.numeric(as.Date(format(Sys.time(), "%Y-%m-%d")))), sum(seq_along(s) * s, na.rm = TRUE))
  for (f in want[[j]]) add(f, c(1, j - 1), sum(switch(f, xtod = s %% 86400, xyr = as.numeric(format(ct, "%Y")), xdom = as.numeric(format(ct, "%d")),
                                                       xmd = as.numeric(format(ct, "%m")) * 100 + as.numeric(format(ct, "%d"))), na.rm = TRUE))
}
# read.systat(to.data.frame = FALSE): the same files read as the list (names as the labels stand, no make.names or make.unique)
for (i in 1:24) syscases(i, if (i == 1) file.path(sysdir, "foreign_iris.syd") else if (i == 2) file.path(sysdir, "foreign_hillrace.syd") else file.path(sysdir, sprintf("foreign_sys%d.sys", i)), raw = TRUE)
# write.arff with an eol ("we", the layout of "wx", files foreign_arffe1 to 4): every line but @data ends in it
eols <- c("\r\n", "\r", "||", "\n\n")
for (i in 1:4) wxcase(i, "arffe", eols[i], "we")
# write.dbf with factor columns and max_nchar: "wf" args (i, ncols, nrows, max_nchar, factor2char, kind[nc] (0 double 1 integer 2 logical 3 character of that many a's, 4 date as yyyymmdd, 5 factor with levels
# L1 to L5, the value its code), values col-major, NaN for NA): 1 when the bytes Neper writes equal the file R wrote past the date bytes 1 to 3 (files foreign_dbff1 to 9; character lengths run to 300)
maxns <- c(254, 254, 254, 5, 10, 1, 3, 254, 7)
for (i in 1:9) {
  n <- sample(4:25, 1); nc <- sample(3:6, 1); kinds <- sample(0:5, nc, replace = TRUE); f2c <- as.numeric(i %% 2 == 0)
  if (i <= 3) kinds[1] <- c(5, 3, 3)[i]; if (i == 2) kinds[2] <- 5
  cols <- lapply(seq_len(nc), function(j) { v <- switch(kinds[j] + 1, round(rnorm(n) * 10^sample(0:4, 1), sample(1:4, 1)), as.numeric(sample(-3000:99999, n, replace = TRUE)), as.numeric(sample(0:1, n, replace = TRUE)), as.numeric(sample(c(1:12, 250, 254, 255, 300), n, replace = TRUE)), as.numeric(format(as.Date("2000-01-01") + sample(0:9000, n, replace = TRUE), "%Y%m%d")), as.numeric(sample(1:5, n, replace = TRUE))); if (runif(1) < 0.7) v[sample(n, 1)] <- NA; v })
  df <- as.data.frame(lapply(seq_len(nc), function(j) { v <- cols[[j]]; switch(kinds[j] + 1, v, as.integer(v), as.logical(v), ifelse(is.na(v), NA_character_, vapply(v, function(k) strrep("a", k), "")), as.Date(ifelse(is.na(v), NA, format(v, scientific = FALSE)), "%Y%m%d"), factor(ifelse(is.na(v), NA, paste0("L", v)), levels = paste0("L", 1:5))) }), stringsAsFactors = FALSE)
  names(df) <- paste0("V", seq_len(nc))
  suppressWarnings(write.dbf(df, file.path(root, sprintf("tests/oracle/data/foreign_dbff%d.dbf", i)), factor2char = f2c == 1, max_nchar = maxns[i]))
  add("wf", c(i, nc, n, maxns[i], f2c, kinds, unlist(cols)), 1)
}
# read.dbf with mixed-case, accented and underscore levels, and Z in field names and values (file foreign_dbf10): R sorts the levels in the session's collation, here the C locale set above, which is Neper's bytewise order
p10 <- file.path(root, "tests/oracle/data/foreign_dbf10.dbf")
e9 <- rawToChar(as.raw(c(0xc3, 0xa9)))
mkdbf(p10, list(fld("ZONE", "C", 6), fld("zZ", "C", 3), fld("Q", "N", 4), fld("Z1", "L", 1)),
      lapply(1:14, function(k) c(c("b", "B", "a", "A", e9, "z", "Z", "ab", "aB", "Ab", "_x", "1x", "Zz", "zZ")[k], c("Z", "z", "ZZ", "zz", "y", "Y", "Zy")[(k - 1) %% 7 + 1], as.character(k * 7), c("T", "F", "Z", "z")[(k - 1) %% 4 + 1])))
dbfcases(10, suppressWarnings(read.dbf(p10, as.is = TRUE))); dbfx(10, p10)
emit("foreign", "foreign", list(cases))
