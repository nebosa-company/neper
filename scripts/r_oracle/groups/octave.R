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
    add("count", c(i, j - 1), length(v)); add("sum", c(i, j - 1), if (is.character(v)) sum(sapply(v, function(z) sum(utf8ToInt(z)))) else sum(as.numeric(v))); add("isum", c(i, j - 1), 0)
  }
}
# bool, complex, range and integer-type variables (7 and 8 are fixed, 9 random); "isum" is the sum of the imaginary parts, 0 for a real value
# An integer type is unknown to read.octave, which gives NULL for it: count 0 and sum 0.
writeLines(c("# Created by Octave 8.4.0, Mon Nov 16 10:00:00 2026 UTC <test@host>",
             "# name: flag", "# type: bool", "1",
             "# name: flags", "# type: bool matrix", "# rows: 2", "# columns: 3", " 1 0 1", " 0 0 1",
             "# name: z", "# type: complex scalar", "(1.5,-2)",
             "# name: zm", "# type: complex matrix", "# rows: 2", "# columns: 2", " (1,2) (3,-4)", " (5,6) (7,8)",
             "# name: rg", "# type: range", "# base, limit, increment", "1 10 3",
             "# name: nn", "# type: int32 scalar", "5"),
           file.path(root, "tests/oracle/data/octave_7.txt"))
for (i in 8:9) {
  nb <- sample(1:5, 1); nl <- nb + sample(4:30, 1); ni <- sample(1:4, 1)
  r <- sample(2:4, 1); cc <- sample(2:4, 1)
  re <- matrix(sample(-9:9, r * cc, replace = TRUE), r, cc); im <- matrix(sample(-9:9, r * cc, replace = TRUE), r, cc)
  cells <- sapply(seq_len(r * cc), function(k) sprintf("(%d,%d)", re[k], im[k]))
  rows <- sapply(seq_len(r), function(k) paste0(" ", paste(cells[((k - 1) * cc + 1):(k * cc)], collapse = " ")))
  bm <- matrix(sample(0:1, 6, replace = TRUE), 2, 3)
  lines <- c("# Created by Octave 8.4.0, Mon Nov 16 10:00:00 2026 UTC <test@host>",
             "# name: rg", "# type: range", "# base, limit, increment", sprintf("%d %d %d", nb, nl, ni),
             "# name: zm", "# type: complex matrix", sprintf("# rows: %d", r), sprintf("# columns: %d", cc), rows,
             "# name: bm", "# type: bool matrix", "# rows: 2", "# columns: 3", apply(bm, 1, function(row) paste0(" ", paste(row, collapse = " "))),
             "# name: nn", "# type: int32 matrix", "# rows: 1", "# columns: 2", " 4 7")
  writeLines(lines, file.path(root, sprintf("tests/oracle/data/octave_%d.txt", i)))
}
for (i in 7:9) {
  d <- read.octave(file.path(root, sprintf("tests/oracle/data/octave_%d.txt", i)))
  add("nvars", c(i, 0), length(d))
  for (j in seq_along(d)) {
    v <- d[[j]]
    add("count", c(i, j - 1), length(v))
    add("sum", c(i, j - 1), if (is.character(v)) sum(sapply(v, function(z) sum(utf8ToInt(z)))) else sum(as.numeric(suppressWarnings(v))))
    add("isum", c(i, j - 1), if (is.complex(v)) sum(Im(v)) else 0)
  }
}
# N-d arrays and string arrays (files 10 and 11)
for (i in 10:11) {
  d3 <- sample(2:4, 3, replace = TRUE); x <- round(rnorm(prod(d3)) * 4, 4); words <- replicate(sample(2:4, 1), paste(sample(letters, sample(1:6, 1), replace = TRUE), collapse = ""))
  lines <- c("# Created by Octave 8.4.0, Mon Nov 16 10:00:00 2026 UTC <test@host>",
             "# name: nd", "# type: matrix", "# ndims: 3", paste0(" ", paste(d3, collapse = " ")), paste0(" ", sprintf("%.15g", x)),
             "# name: sa", "# type: string", sprintf("# elements: %d", length(words)),
             as.vector(rbind(sprintf("# length: %d", nchar(words)), words)))
  writeLines(lines, file.path(root, sprintf("tests/oracle/data/octave_%d.txt", i)))
  d <- read.octave(file.path(root, sprintf("tests/oracle/data/octave_%d.txt", i)))
  add("nvars", c(i, 0), length(d))
  for (j in seq_along(d)) { v <- d[[j]]; add("count", c(i, j - 1), length(v)); add("sum", c(i, j - 1), if (is.character(v)) sum(sapply(v, function(z) sum(utf8ToInt(z)))) else sum(as.numeric(v))); add("isum", c(i, j - 1), 0) }
}
# lists, old-style structs and cells (files 12 and 13); sum is recursive
rs <- function(v) if (is.list(v)) sum(vapply(v, rs, 0)) else if (is.character(v)) sum(sapply(v, function(z) sum(utf8ToInt(z)))) else sum(as.numeric(suppressWarnings(v)))
ri <- function(v) if (is.list(v)) sum(vapply(v, ri, 0)) else if (is.complex(v)) sum(Im(v)) else 0
sc <- function(x) c("# name: <cell-element>", "# type: scalar", sprintf("%.15g", x))
mt <- function(m) c("# name: <cell-element>", "# type: matrix", sprintf("# rows: %d", nrow(m)), sprintf("# columns: %d", ncol(m)), apply(m, 1, function(row) paste0(" ", paste(sprintf("%.15g", row), collapse = " "))))
st <- function(s) c("# name: <cell-element>", "# type: string", "# elements: 1", sprintf("# length: %d", nchar(s)), s)
cz <- function(z) c("# name: <cell-element>", "# type: complex scalar", sprintf("(%g,%g)", Re(z), Im(z)))
for (i in 12:13) {
  nr <- sample(1:3, 1); nc <- sample(1:3, 1); w <- paste(sample(letters, 4), collapse = "")
  cellel <- unlist(lapply(seq_len(nc), function(j) c(unlist(lapply(seq_len(nr), function(r) switch(sample(1:4, 1), sc(round(rnorm(1), 4)), mt(matrix(round(rnorm(4), 4), 2, 2)), st(w), cz(complex(real = sample(1:9, 1), imaginary = sample(1:9, 1)))))), ""))) 
  n3 <- sample(2:4, 1)
  lines <- c("# Created by Octave 8.4.0, Mon Nov 16 10:00:00 2026 UTC <test@host>",
             "# name: cc", "# type: cell", sprintf("# rows: %d", nr), sprintf("# columns: %d", nc), cellel,
             "# name: ll", "# type: list", sprintf("# length: %d", n3), unlist(lapply(1:n3, function(k) if (k %% 2 == 0) sc(round(rnorm(1), 4)) else st(w))),
             "# name: ss", "# type: struct", "# length: 2", "# name: a", "# type: scalar", "2.5", "# name: b", "# type: matrix", "# rows: 1", "# columns: 3", " 1 2 3",
             "# name: after", "# type: scalar", "7", "# name: sq", "# type: scalar struct", "# ndims: 2", " 1 1", "# length: 1", "# name: k", "# type: scalar", "9",
             "# name: last", "# type: scalar", "3")
  writeLines(lines, file.path(root, sprintf("tests/oracle/data/octave_%d.txt", i)))
  d <- suppressWarnings(read.octave(file.path(root, sprintf("tests/oracle/data/octave_%d.txt", i))))
  add("nvars", c(i, 0), length(d))
  for (j in seq_along(d)) { v <- d[[j]]; add("count", c(i, j - 1), length(v)); add("sum", c(i, j - 1), rs(v)); add("isum", c(i, j - 1), ri(v)) }
}
# Inf, -Inf, NaN and NA as Octave writes them (file 14): scalars and matrix entries; the sums are Inf, -Inf or NaN
writeLines(c("# Created by Octave 8.4.0, Mon Nov 16 10:00:00 2026 UTC <test@host>",
             "# name: pi", "# type: scalar", "Inf", "# name: ni", "# type: scalar", "-Inf", "# name: nn", "# type: scalar", "NaN", "# name: na", "# type: scalar", "NA",
             "# name: m1", "# type: matrix", "# rows: 2", "# columns: 2", " 1 Inf", " 2 3", "# name: m2", "# type: matrix", "# rows: 1", "# columns: 3", " -Inf 5 6",
             "# name: m3", "# type: matrix", "# rows: 1", "# columns: 3", " NaN NA 1", "# name: m4", "# type: matrix", "# rows: 1", "# columns: 2", " NA 4"),
           file.path(root, "tests/oracle/data/octave_14.txt"))
d <- read.octave(file.path(root, "tests/oracle/data/octave_14.txt"))
add("nvars", c(14, 0), length(d))
for (j in seq_along(d)) { v <- d[[j]]; add("count", c(14, j - 1), length(v)); add("sum", c(14, j - 1), sum(as.numeric(v))); add("isum", c(14, j - 1), 0) }
# layout: wsum/wisum weight every value (imaginary part) by its 1-based position in R's own (column-major) order, recursively through lists and cells,
# so a transposed matrix or reordered element fails; dimr is nrow*1000+ncol of a matrix, and nhash weights each name byte by its position.
wl <- function(v) if (is.list(v)) sum(vapply(v, wl, 0)) else if (is.character(v) || is.null(v)) 0 else { x <- suppressWarnings(as.numeric(Re(v))); sum(x * seq_along(x)) }
wi <- function(v) if (is.list(v)) sum(vapply(v, wi, 0)) else if (is.complex(v)) sum(Im(v) * seq_along(v)) else 0
# multi-digit "# rows", "# columns", "# elements" and "# length" (file 15; no random draws, so earlier files are unchanged)
m15 <- matrix(round(sin(1:132) * 7, 4), 12, 11)
w15 <- c("abcdefghijkl", "x", "yz", "0123456789", "q", "rs", "tuv", "w", "mnopqrstuvwxyz", "a b", "end")
writeLines(c("# Created by Octave 8.4.0, Mon Nov 16 10:00:00 2026 UTC <test@host>",
             "# name: big", "# type: matrix", "# rows: 12", "# columns: 11", apply(m15, 1, function(row) paste0(" ", paste(sprintf("%.15g", row), collapse = " "))),
             "# name: words", "# type: string", sprintf("# elements: %d", length(w15)), as.vector(rbind(sprintf("# length: %d", nchar(w15)), w15))),
           file.path(root, "tests/oracle/data/octave_15.txt"))
d <- read.octave(file.path(root, "tests/oracle/data/octave_15.txt"))
add("nvars", c(15, 0), length(d))
for (j in seq_along(d)) { v <- d[[j]]; add("count", c(15, j - 1), length(v)); add("sum", c(15, j - 1), if (is.character(v)) sum(sapply(v, function(z) sum(utf8ToInt(z)))) else sum(as.numeric(v))); add("isum", c(15, j - 1), 0) }
for (i in 1:15) {
  d <- suppressWarnings(read.octave(file.path(root, sprintf("tests/oracle/data/octave_%d.txt", i))))
  for (j in seq_along(d)) {
    v <- d[[j]]
    add("wsum", c(i, j - 1), wl(v)); add("wisum", c(i, j - 1), wi(v))
    add("nhash", c(i, j - 1), sum(as.numeric(utf8ToInt(names(d)[j])) * seq_len(nchar(names(d)[j]))))
    if (is.matrix(v)) add("dimr", c(i, j - 1), nrow(v) * 1000 + ncol(v))
  }
}
emit("octave", "foreign", list(cases))
