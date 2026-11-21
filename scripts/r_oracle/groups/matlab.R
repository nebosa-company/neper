# R.matlab: readMat of MAT files, level 4 and level 5 (uncompressed, compressed v7, little and big endian), and writeMat bytes.
#   Files: tests/oracle/data/matlab_<i>.mat. Files 1-9 come from writeMat; 10-20 are built byte by byte here (builders below) and read by readMat.
#   args: (file, p0, p1, p2, aux) where p0 is the 0-based variable, p1 and p2 index the children of a cell or struct (-1 stops), aux is an axis.
#   fn: "nvars" "name" (code point sum of a variable name) "count" (R length) "sum" "wsum" (sum weighted by 1-based position) "isum" "wisum" (imaginary
#   parts) "ndim" "dim" (R's dim(), a struct gains the field count as first axis), "rewrite" (writeMat bytes after the header against the Neper
#   writer fed the parsed file; want 0), "selfrt" (parse, write, parse again; want 0).
#   Sparse matrices are read with sparseMatrixClass = "matrix" (dense), which holds the same values as the default Matrix class.
suppressMessages(library(R.matlab))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-12, abs = 1e-12)
root <- Sys.getenv("NEPER_ROOT", unset = getwd())
dir.create(file.path(root, "tests/oracle/data"), recursive = TRUE, showWarnings = FALSE)
fpath <- function(i) file.path(root, sprintf("tests/oracle/data/matlab_%d.mat", i))

# ---- byte builders ----
E <- "little"
u32 <- function(x) writeBin(as.integer(x), raw(), size = 4, endian = E)
pad8 <- function(n) (8 - n %% 8) %% 8
enc <- function(x, type) switch(as.character(type),
  "1" = writeBin(as.integer(x), raw(), size = 1), "2" = writeBin(as.integer(x), raw(), size = 1),
  "3" = writeBin(as.integer(x), raw(), size = 2, endian = E), "4" = writeBin(as.integer(x), raw(), size = 2, endian = E),
  "5" = writeBin(as.integer(x), raw(), size = 4, endian = E), "6" = writeBin(as.integer(x), raw(), size = 4, endian = E),
  "7" = writeBin(as.numeric(x), raw(), size = 4, endian = E), "16" = writeBin(as.integer(x), raw(), size = 1), "9" = writeBin(as.numeric(x), raw(), size = 8, endian = E))
el <- function(type, payload, small = FALSE) {
  n <- length(payload)
  if (small && n <= 4 && n > 0) c(u32(type + n * 65536), payload, raw(4 - n))
  else c(u32(type), u32(n), payload, raw(pad8(n)))
}
mx <- function(name, cls, dims, re = NULL, im = NULL, rtype = 9, logical = FALSE, global = FALSE, nzmax = 0, body = NULL, small = FALSE) {
  fl <- cls + 256 * (2 * logical + 4 * global + 8 * !is.null(im))
  inner <- c(el(6, c(u32(fl), u32(nzmax))), el(5, enc(dims, 5)), el(1, charToRaw(name), small = TRUE))
  if (!is.null(body)) inner <- c(inner, body)
  else if (!is.null(re)) { inner <- c(inner, el(rtype, enc(re, rtype), small)); if (!is.null(im)) inner <- c(inner, el(rtype, enc(im, rtype), small)) }
  c(u32(14), u32(length(inner)), inner)
}
cmp <- function(m) { z <- memCompress(m, "gzip"); c(u32(15), u32(length(z)), z) }
hdr <- function() {
  h <- raw(128); h[1:19] <- charToRaw("MATLAB 5.0 MAT-file")
  if (E == "little") h[125:128] <- as.raw(c(0, 1, 0x49, 0x4d)) else h[125:128] <- as.raw(c(1, 0, 0x4d, 0x49))
  h
}
sparse_mx <- function(name, nr, nc, ir, jc, pr, nzmax = length(ir), logical = FALSE)
  mx(name, 5, c(nr, nc), nzmax = nzmax, logical = logical,
     body = if (nzmax > 0) c(el(5, enc(ir, 5)), el(5, enc(jc, 5)), if (logical) el(2, enc(pr, 2)) else el(9, enc(pr, 9))) else NULL)
cell_mx <- function(name, dims, elems) mx(name, 1, dims, body = unlist(elems))
struct_mx <- function(name, dims, fnames, vals) {  # vals: one list per element of one raw matrix per field
  len <- max(4, max(nchar(fnames)) + 1)
  fn <- unlist(lapply(fnames, function(s) c(charToRaw(s), raw(len - nchar(s)))))
  body <- c(el(5, u32(len), small = TRUE), el(1, fn))
  for (v in vals) for (f in v) body <- c(body, f)
  mx(name, 2, dims, body = body)
}
chr_mx <- function(name, dims, s, rtype = 4) mx(name, 4, dims, re = utf8ToInt(s), rtype = rtype)
num <- function(re, dims = c(1, length(re)), name = "", ...) mx(name, 6, dims, re = re, ...)
l4 <- function(name, P, T, mr, nc, re, im = NULL) {
  ty <- c(9, 7, 5, 3, 4, 2)[P + 1]
  c(u32((E == "big") * 1000 + P * 10 + T), u32(mr), u32(nc), u32(!is.null(im)), u32(nchar(name) + 1), charToRaw(name), as.raw(0),
    enc(re, ty), if (!is.null(im)) enc(im, ty))
}
put <- function(i, ...) writeBin(c(hdr(), unlist(list(...))), fpath(i))

# ---- digests ----
unwrap <- function(x) if (is.list(x) && length(x) == 1 && is.null(dim(x)) && (is.null(names(x)) || identical(names(x), ""))) x[[1]] else x
walk <- function(i, v, path) {
  if (is.null(v)) return(invisible())
  pa <- c(path, rep(-1, 3 - length(path)))
  A <- function(fn, want, aux = -1) add(fn, c(i, pa, aux), want)
  if (is.list(v)) {
    A("count", length(v))
    if (!is.null(dim(v))) { A("ndim", length(dim(v))); for (k in seq_along(dim(v))) A("dim", dim(v)[k], k - 1) }
    if (length(path) < 3) for (k in seq_along(v)) walk(i, unwrap(v[[k]]), c(path, k - 1))
  } else if (is.character(v)) {
    cp <- utf8ToInt(paste(v, collapse = ""))
    A("count", length(v)); A("sum", sum(cp)); A("wsum", sum(cp * seq_along(cp)))
  } else {
    x <- as.numeric(Re(v)); n <- seq_along(x)
    A("count", length(v)); A("sum", sum(x)); A("wsum", sum(x * n))
    if (!is.null(dim(v))) { A("ndim", length(dim(v))); for (k in seq_along(dim(v))) A("dim", dim(v)[k], k - 1) }
    if (is.complex(v)) { y <- Im(v); A("isum", sum(y)); A("wisum", sum(y * n)) }
  }
}
check <- function(i, writable = TRUE) {
  d <- readMat(fpath(i), sparseMatrixClass = "matrix")
  add("nvars", c(i, -1, -1, -1, -1), length(d))
  for (j in seq_along(d)) {
    add("name", c(i, j - 1, -1, -1, -1), sum(utf8ToInt(gsub(".", "_", names(d)[j], fixed = TRUE))))
    walk(i, d[[j]], j - 1)
  }
  if (writable) add("selfrt", c(i, -1, -1, -1, -1), 0)
}
# ---- files 1-6: writeMat of doubles, integers and a string ----
set.seed(20261226)
for (i in 1:6) {
  r <- sample(2:6, 1); cc <- sample(2:5, 1)
  a <- matrix(round(rnorm(r * cc) * 10, 5), r, cc); b <- round(rnorm(sample(3:9, 1)), 6)
  im <- matrix(sample(-50:500, r * 2, replace = TRUE), r, 2); storage.mode(im) <- "integer"
  s <- paste(sample(letters, sample(2:9, 1), replace = TRUE), collapse = "")
  writeMat(fpath(i), alpha = a, beta = b, gamma = im, delta = s)
  check(i)
  add("rewrite", c(i, -1, -1, -1, -1), 0)
}
# ---- files 7-9: writeMat of structs, complex, logical, cell of strings, long names, arrays, empties ----
writeMat(fpath(7), st = list(x = 1:3, y = "hi", z = matrix(c(1.5, 2.5, -3, 4), 2)),
         emptystruct = list(only = numeric(0)))
check(7); add("rewrite", c(7, -1, -1, -1, -1), 0)
writeMat(fpath(8), cx = matrix(c(1 + 2i, 3 - 1i, -2.5 + 0.5i, 0 + 7i), 2), lg = matrix(c(TRUE, FALSE, TRUE, TRUE), 2),
         ints = matrix(c(-5L, 7L, 2147483647L, 0L, 3L, 9L), 2), words = matrix(c("ab", "cde", "f", "ghij"), 2), cv = c(1 + 1i, 2 - 2i, 3))
check(8); add("rewrite", c(8, -1, -1, -1, -1), 0)
writeMat(fpath(9), a_long_name = array(round(rnorm(12), 4), c(2, 3, 2)), nothing = numeric(0), scalar = 2.5, intscalar = 7L,
         wordlist = c("alpha", "be", "gamma"), longstringvariable = "The quick brown fox")
check(9); add("rewrite", c(9, -1, -1, -1, -1), 0)

# ---- files 10-13: level 5 numeric kinds (stored type differs from class), plain / compressed / big endian ----
mk_numeric <- function() {
  set.seed(71)
  list(
    num("a1", dims = c(3, 2), re = round(rnorm(6) * 7, 4)),
    mx("a2", 6, c(2, 2), re = c(1, 2, 3, 250), rtype = 2),
    mx("a3", 6, c(2, 3), re = c(-5, 300, 12, -32000, 4, 0), rtype = 3),
    mx("a4", 6, c(2, 2), re = c(-100000, 5, 99999, -1), rtype = 5),
    mx("a5", 7, c(2, 2), re = round(rnorm(4), 3), rtype = 7),
    mx("a6", 8, c(2, 2), re = c(-128, 127, 5, -7), rtype = 1),
    mx("a7", 9, c(2, 3), re = c(0, 255, 17, 3, 9, 200), rtype = 2),
    mx("a8", 10, c(1, 4), re = c(-300, 32767, 1, -32768), rtype = 3),
    mx("a9", 11, c(1, 3), re = c(0, 65535, 1234), rtype = 4),
    mx("a10", 12, c(2, 2), re = c(-2147483647, 2147483647, 7, -9), rtype = 5),
    mx("a11", 13, c(1, 3), re = c(0, 2147483647, 4000), rtype = 6),
    mx("a12", 9, c(2, 3), re = c(1, 0, 1, 1, 0, 0), rtype = 2, logical = TRUE),
    mx("a13", 6, c(2, 2), re = round(rnorm(4), 4), im = round(rnorm(4), 4)),
    mx("a14", 7, c(2, 1), re = c(0.5, -1.25), im = c(3.75, 8), rtype = 7),
    mx("a15", 6, c(2, 3, 2), re = round(rnorm(12), 3)),
    mx("a16", 6, c(0, 0), re = numeric(0)),
    mx("a17", 6, c(1, 0), re = numeric(0)),
    mx("a18", 6, c(1, 1), re = 42.5, global = TRUE),
    mx("a19", 6, c(1, 5), re = c(10, 20, 30, 40, 50), rtype = 4),
    mx("a20", 9, c(2, 2), re = c(7, 8, 9, 10), rtype = 9),
    mx("a21", 6, c(1, 1), re = 3, rtype = 2),
    mx("a22", 6, c(2, 2), re = c(1e300, -1e-300, 0.1, 5e-324)),
    mx("a23", 6, c(1, 4), re = c(1, 2, 3, 4), rtype = 7),
    mx("a24", 6, c(1, 3), re = c(-1, -2, 1000), rtype = 3, im = c(1, 2, 3)),
    mx("a25", 6, c(1, 1), re = 7, rtype = 2, small = TRUE),
    mx("a26", 6, c(1, 2), re = c(-3, 900), rtype = 3, small = TRUE),
    mx("a27", 4, c(1, 2), re = utf8ToInt("ab"), rtype = 4, small = TRUE),
    mx("a28", 6, c(1, 4), re = c(1, 2, 3, 4), rtype = 2, small = TRUE)
  )
}
E <- "little"; put(10, mk_numeric()); check(10)
put(11, lapply(mk_numeric(), cmp)); check(11)
E <- "big"; put(12, mk_numeric()); check(12)
put(13, lapply(mk_numeric(), cmp)); check(13)
E <- "little"

# ---- files 14-16: structs, cells, sparse, characters ----
mk_nested <- function() {
  set.seed(72)
  inner_cell <- cell_mx("", c(1, 2), list(num(2.5, c(1, 1)), chr_mx("", c(1, 2), "hi")))
  list(
    struct_mx("s1", c(1, 1), c("alpha", "b", "gamma_long_name", "nested"), list(list(
      num(c(1, 2, 3), c(1, 3)), chr_mx("", c(1, 5), "hello"), num(round(rnorm(4), 3), c(2, 2)),
      struct_mx("", c(1, 1), c("x", "y"), list(list(num(9, c(1, 1)), inner_cell)))))),
    struct_mx("s2", c(1, 2), c("x", "name"), list(list(num(1, c(1, 1)), chr_mx("", c(1, 3), "one")), list(num(c(4, 5), c(1, 2)), chr_mx("", c(1, 3), "two")))),
    cell_mx("c1", c(2, 2), list(num(round(rnorm(6), 3), c(2, 3)), chr_mx("", c(1, 3), "abc"),
      cell_mx("", c(1, 2), list(num(1, c(1, 1)), num(c(1, 2), c(1, 2)))), mx("", 6, c(0, 0), re = numeric(0)))),
    cell_mx("c2", c(1, 3), list(struct_mx("", c(1, 1), c("k"), list(list(num(c(3, 4), c(2, 1))))),
      mx("", 9, c(1, 3), re = c(1, 0, 1), rtype = 2, logical = TRUE), mx("", 6, c(2, 1), re = c(1, 2)))),
    cell_mx("c3", c(0, 0), list()),
    struct_mx("s3", c(2, 1), c("f1", "f2", "f3"), list(list(num(1, c(1, 1)), num(2, c(1, 1)), chr_mx("", c(1, 1), "q")),
                                                      list(num(3, c(1, 1)), num(4, c(1, 1)), chr_mx("", c(1, 2), "rs")))),
    chr_mx("ch1", c(3, 4), "aeibfjcgkdhl"),
    chr_mx("ch2", c(1, 5), "hello", rtype = 16),
    chr_mx("ch3", c(1, 6), "bytes!", rtype = 2),
    chr_mx("ch4", c(2, 3), "adbecf", rtype = 16),
    sparse_mx("sp1", 4, 5, c(0, 2, 1, 3, 3), c(0, 1, 2, 2, 4, 5), c(1.5, -2, 3.25, 4, 5)),
    sparse_mx("sp2", 3, 3, c(0, 2, 1), c(0, 1, 2, 3), c(1, 1, 1), logical = TRUE),
    sparse_mx("sp3", 2, 2, integer(0), c(0, 0, 0), numeric(0), nzmax = 0),
    sparse_mx("sp4", 3, 2, c(0, 1, 2, 0), c(0, 3, 3), c(1, 2, 3, 99), nzmax = 4)
  )
}
nested_plain <- mk_nested()
put(14, nested_plain); check(14, writable = FALSE)
put(15, lapply(seq_along(nested_plain), function(k) if (k %% 2 == 0) cmp(nested_plain[[k]]) else nested_plain[[k]])); check(15, writable = FALSE)
E <- "big"; nested_big <- mk_nested()
put(16, nested_big); check(16, writable = FALSE)
put(17, lapply(nested_big, cmp)); check(17, writable = FALSE)
E <- "little"
# the same structures without sparse matrices, through the writer
no_sparse <- nested_plain[1:10]
put(18, no_sparse); check(18)
put(19, lapply(no_sparse, cmp)); check(19)

# ---- files 20-21: level 4 ----
mk_l4 <- function() {
  set.seed(73)
  c(l4("m1", 0, 0, 3, 2, round(rnorm(6) * 5, 4)), l4("m2", 1, 0, 2, 2, c(0.5, -1.25, 3, 8)), l4("m3", 2, 0, 2, 3, c(-5, 70000, 9, 0, -2147483647, 4)),
    l4("m4", 3, 0, 2, 2, c(-300, 32767, 5, -1)), l4("m5", 4, 0, 1, 4, c(0, 65535, 17, 300)), l4("m6", 5, 0, 3, 1, c(0, 255, 7)),
    l4("cx", 0, 0, 2, 2, c(1, 2, 3, 4), c(-1, 0.5, 2, 8)), l4("tx", 0, 1, 2, 3, utf8ToInt("acebdf")), l4("ty", 5, 1, 3, 2, utf8ToInt("abcdef")),
    l4("sp", 0, 2, 4, 3, c(1, 3, 3, 3, 1, 2, 3, 3, 5, -6, 7, 0)), l4("sq", 0, 2, 3, 3, c(2, 1, 3, 1, 3, 4, 4, 9, 0)), l4("em", 0, 0, 0, 0, numeric(0)))
}
E <- "little"; put_raw <- function(i, b) writeBin(b, fpath(i))
put_raw(20, mk_l4()); check(20, writable = FALSE)
E <- "big"; put_raw(21, mk_l4()); check(21, writable = FALSE)
E <- "little"

emit("matlab", "R.matlab", list(cases))
