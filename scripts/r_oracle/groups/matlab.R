# R.matlab: readMat of level 5 files written by writeMat (double and integer arrays, a character string).
#   Files: tests/oracle/data/matlab_<i>.mat; args: (i, var)   fn "nvars" "count" (elements of the variable) "sum" (the sum of its values; of the code points for a string)
suppressMessages(library(R.matlab))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-12, abs = 1e-12)
set.seed(20261226)
root <- Sys.getenv("NEPER_ROOT", unset = getwd())
dir.create(file.path(root, "tests/oracle/data"), recursive = TRUE, showWarnings = FALSE)
for (i in 1:6) {
  r <- sample(2:6, 1); cc <- sample(2:5, 1)
  a <- matrix(round(rnorm(r * cc) * 10, 5), r, cc); b <- round(rnorm(sample(3:9, 1)), 6)
  im <- matrix(sample(-50:500, r * 2, replace = TRUE), r, 2); storage.mode(im) <- "integer"
  s <- paste(sample(letters, sample(2:9, 1), replace = TRUE), collapse = "")
  path <- file.path(root, sprintf("tests/oracle/data/matlab_%d.mat", i))
  writeMat(path, alpha = a, beta = b, gamma = im, delta = s)
  d <- readMat(path)
  add("nvars", c(i, 0), length(d))
  for (j in seq_along(d)) {
    v <- d[[j]]
    add("count", c(i, j - 1), length(v)); add("sum", c(i, j - 1), if (is.character(v)) sum(utf8ToInt(v)) else sum(as.numeric(v)))
  }
}
emit("matlab", "R.matlab", list(cases))
