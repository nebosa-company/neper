# foreign::read.S of binary S-PLUS objects (the "\0S data\1" files) written here, half of them big-endian: tests/oracle/data/sbin_<i>.bin, sbin_e<i>.bin for the errors.
#   args (file, 0). fn: len, sum, wsum, nna, nlev, levs, ndim, dimprod, nnames, elh as in the foreign_sdump group; "eerr" is 1 when read.S stops with an error.
suppressMessages(library(foreign))
cases <- list()
add <- function(fn, args, want) if (length(want) != 1 || is.na(want)) stop(paste("NA want", fn, paste(args, collapse = ","))) else cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-12, abs = 1e-12)
root <- Sys.getenv("NEPER_ROOT", unset = getwd())
dir.create(file.path(root, "tests/oracle/data"), recursive = TRUE, showWarnings = FALSE)
set.seed(20261233)
cu <- function(s) sum(as.numeric(utf8ToInt(s)))
hasht <- function(nm) if (length(nm) == 0) 0 else sum(vapply(seq_along(nm), function(i) cu(nm[i]) * i, 0))
rs <- function(v) if (is.list(v)) sum(vapply(unclass(v), rs, 0)) else if (is.character(v)) sum(vapply(v[!is.na(v)], cu, 0)) else sum(as.numeric(unclass(v)), na.rm = TRUE)
rw <- function(v) if (is.list(v)) sum(vapply(unclass(v), rw, 0)) else { x <- if (is.character(v)) vapply(ifelse(is.na(v), "", v), cu, 0) else as.numeric(unclass(v)); ok <- !is.na(v); sum(x[ok] * seq_along(x)[ok]) }
rn <- function(v) if (is.list(v)) sum(vapply(unclass(v), rn, 0)) else sum(is.na(v))
BE <- FALSE
i32 <- function(x) writeBin(as.integer(x), raw(), size = 4, endian = if (BE) "big" else "little")
strs <- function(x) { b <- unlist(lapply(x, function(s) c(charToRaw(s), as.raw(0)))); c(i32(length(b)), b) }
# enc(v, pos): list(code, len, raw) for v whose data starts at absolute byte pos
enc <- function(v, pos) {
  if (is.factor(v)) return(encs(list(.Data = as.integer(v), .Label = levels(v), class = "factor"), pos))
  if (is.data.frame(v)) return(encs(list(.Data = unclass(v)[seq_along(v)], row.names = row.names(v), class = "data.frame"), pos))
  if (is.matrix(v)) return(encs(list(.Data = as.vector(v), .Dim = dim(v)), pos))
  if (is.list(v)) { e <- encl(v, pos); return(list(code = 6, len = length(v), raw = e)) }
  if (is.logical(v)) return(list(code = 1, len = length(v), raw = i32(ifelse(is.na(v), NA_integer_, as.integer(v)))))
  if (is.integer(v)) return(list(code = 2, len = length(v), raw = i32(ifelse(is.na(v), NA_integer_, v))))
  if (is.character(v)) return(list(code = 5, len = length(v), raw = strs(v)))
  if (isTRUE(attr(v, "single"))) return(list(code = 3, len = length(v), raw = writeBin(as.numeric(v), raw(), size = 4, endian = if (BE) "big" else "little")))
  list(code = 4, len = length(v), raw = writeBin(as.numeric(v), raw(), size = 8, endian = if (BE) "big" else "little"))
}
encs <- function(l, pos) { e <- encl(l, pos); list(code = 21, len = length(l), raw = e) }
encl <- function(l, pos) {
  k <- length(l)
  nm <- if (is.null(names(l))) rep("", k) else names(l)
  nb <- strs(nm)
  p <- pos + length(nb) + 12 * k
  parts <- list(); codes <- integer(k); lens <- integer(k); offs <- integer(k)
  for (j in seq_len(k)) {
    el <- enc(l[[j]], p)
    codes[j] <- el$code; lens[j] <- el$len; offs[j] <- p
    parts[[j]] <- el$raw
    p <- p + length(el$raw)
  }
  c(nb, i32(codes), i32(lens), i32(offs), unlist(parts))
}
writeS <- function(path, v) {
  e <- enc(v, 16)
  writeBin(c(as.raw(c(0, 83, 32, 100, 97, 116, 97, 1)), i32(e$code), i32(e$len), e$raw), path)
}
ndig <- function(x) round(x, sample(0:5, 1))
words <- function(n) vapply(seq_len(n), function(i) paste(sample(letters, sample(1:9, 1), replace = TRUE), collapse = ""), "")
dbl <- function(n, single = FALSE) { x <- ndig(rnorm(n) * 10^sample(-2:4, 1)); x[sample(n, 1)] <- NA; if (single) x <- as.numeric(as.single(x)); attr(x, "single") <- single; x }
gen <- function(kind) switch(kind,
  { x <- dbl(sample(1:9, 1)); x },
  sample(c(-50:200, NA), sample(1:9, 1), replace = TRUE),
  sample(c(TRUE, FALSE, NA), sample(1:7, 1), replace = TRUE),
  words(sample(1:6, 1)),
  dbl(sample(2:6, 1), TRUE),
  factor(sample(c("a", "bc", "def", "x y"), 7, replace = TRUE)),
  matrix(ndig(rnorm(12) * 100), sample(c(2, 3, 4), 1)),
  list(dbl(3), words(2), TRUE),
  list(p = dbl(4), q = list(r = 1:3, s = c("u", "v")), t = factor(c("lo", "hi", "lo"))),
  data.frame(f = factor(sample(c("m", "n"), 4, replace = TRUE)), i = c(NA, sample(1:9, 3)), d = dbl(4), l = c(TRUE, NA, FALSE, TRUE), s = words(4), stringsAsFactors = FALSE))
for (i in 1:20) {
  BE <- i %% 2 == 0
  v <- gen((i - 1) %% 10 + 1)
  path <- file.path(root, sprintf("tests/oracle/data/sbin_%d.bin", i))
  writeS(path, v)
  r <- suppressWarnings(read.S(path))
  add("len", c(i, 0), length(r)); add("sum", c(i, 0), rs(r)); add("wsum", c(i, 0), rw(r)); add("nna", c(i, 0), rn(r))
  lv <- levels(r); add("nlev", c(i, 0), length(lv)); add("levs", c(i, 0), if (length(lv)) sum(vapply(lv, cu, 0)) else 0)
  d <- attr(r, "dim"); add("ndim", c(i, 0), length(d)); add("dimprod", c(i, 0), if (is.null(d)) 0 else prod(d))
  add("nnames", c(i, 0), length(names(r))); add("elh", c(i, 0), hasht(names(r)))
}
# errors: not an S object, and a code that is out of range in both byte orders
BE <- FALSE
good <- readBin(file.path(root, "tests/oracle/data/sbin_1.bin"), "raw", 1000)
errs <- list(good[-1], c(good[1:8], as.raw(c(255, 255, 255, 127)), good[13:length(good)]), as.raw(1:5), c(as.raw(c(0, 83, 32, 100, 97, 116, 97, 2)), good[9:length(good)]))
for (i in seq_along(errs)) {
  path <- file.path(root, sprintf("tests/oracle/data/sbin_e%d.bin", i))
  writeBin(errs[[i]], path)
  r <- tryCatch({ suppressWarnings(read.S(path)); TRUE }, error = function(err) FALSE)
  add("eerr", c(i, 0), as.numeric(!r))
}
# a top-level code of exactly 65535 is in range in either byte order: R returns the string "Unrecognized S mode" (not a malformed header); "eunsup" is 1 for that
for (be in c(FALSE, TRUE)) {
  BE <- be
  k <- if (be) 6 else 5
  path <- file.path(root, sprintf("tests/oracle/data/sbin_e%d.bin", k))
  writeBin(c(as.raw(c(0, 83, 32, 100, 97, 116, 97, 1)), i32(65535), i32(1), i32(0)), path)
  msg <- tryCatch(read.S(path), error = function(err) "")
  add("eunsup", c(k, 0), as.numeric(is.character(msg) && length(msg) == 1 && grepl("Unrecognized S mode", msg)))
}
emit("foreign_sbin", "foreign", list(cases))
