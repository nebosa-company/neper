# foreign::read.octave of text files in the format `save -text` writes (scalars, matrices and strings).
#   Files: tests/oracle/data/octave_<i>.txt; args: (i, var)   fn "nvars" "count" (elements) "sum" (values, or the code points of a string)
suppressMessages(library(foreign))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-12, abs = 1e-12)
set.seed(20261227)
root <- Sys.getenv("NEPER_ROOT", unset = getwd())
dir.create(file.path(root, "tests/oracle/data"), recursive = TRUE, showWarnings = FALSE)
for (i in 1:6) {
  r <- sample(2:5, 1); cc <- sample(2:5, 1); m <- matrix(round(rnorm(r * cc) * 5, 5), r, cc); sc <- round(rnorm(1), 6); s <- paste(sample(letters, sample(3:10, 1), replace = TRUE), collapse = "")
  lines <- c("# Created by Octave 8.4.0, Mon Nov 16 10:00:00 2026 UTC <test@host>",
             "# name: sc", "# type: scalar", sprintf("%.15g", sc),
             "# name: mm", "# type: matrix", sprintf("# rows: %d", r), sprintf("# columns: %d", cc),
             apply(m, 1, function(row) paste0(" ", paste(sprintf("%.15g", row), collapse = " "))),
             "# name: txt", "# type: string", "# elements: 1", sprintf("# length: %d", nchar(s)), s)
  path <- file.path(root, sprintf("tests/oracle/data/octave_%d.txt", i))
  writeLines(lines, path)
  d <- read.octave(path)
  add("nvars", c(i, 0), length(d))
  for (j in seq_along(d)) {
    v <- d[[j]]
    add("count", c(i, j - 1), if (is.character(v)) 1 else length(v)); add("sum", c(i, j - 1), if (is.character(v)) sum(utf8ToInt(v)) else sum(as.numeric(v)))
  }
}
emit("octave", "foreign", list(cases))
