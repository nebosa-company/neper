# foreign: read.arff of dense ARFF files written by write.arff (numeric and nominal columns with missing values).
#   The files are written to tests/oracle/data/foreign_arff<i>.arff; args: (i, col)   fn "sum" (the sum of the numeric values or of the factor codes, NA removed)
#   "nas" (the number of missing values in the column) "dim" (col 0 the number of rows, col 1 the number of columns)
suppressMessages(library(foreign))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-12, abs = 1e-12)
set.seed(20261225)
root <- Sys.getenv("NEPER_ROOT", unset = getwd())
dir.create(file.path(root, "tests/oracle/data"), recursive = TRUE, showWarnings = FALSE)
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
  rd <- read.dbf(path, as.is = TRUE)
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
emit("foreign", "foreign", list(cases))
