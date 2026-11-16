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
emit("foreign", "foreign", list(cases))
