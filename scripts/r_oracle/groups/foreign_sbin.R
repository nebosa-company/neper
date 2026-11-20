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
rty <- function(v) if (is.complex(v)) 1 else if (is.name(v)) 2 else if (is.null(v)) 3 else if (is.call(v)) 4 else if (is.function(v)) 5 else if (is.expression(v)) 6 else 0
rs <- function(v) if (rty(v) >= 2) 0 else if (is.complex(v)) sum(Re(v[!is.na(v)])) else if (is.list(v)) sum(vapply(unclass(v), rs, 0)) else if (is.character(v)) sum(vapply(v[!is.na(v)], cu, 0)) else sum(as.numeric(unclass(v)), na.rm = TRUE)
ri <- function(v) if (rty(v) >= 2) 0 else if (is.complex(v)) sum(Im(v[!is.na(v)])) else if (is.list(v)) sum(vapply(unclass(v), ri, 0)) else 0
rw <- function(v) if (rty(v) >= 2) 0 else if (is.list(v)) sum(vapply(unclass(v), rw, 0)) else { x <- if (is.character(v)) vapply(ifelse(is.na(v), "", v), cu, 0) else if (is.complex(v)) Re(v) else as.numeric(unclass(v)); ok <- !is.na(v); sum(x[ok] * seq_along(x)[ok]) }
rn <- function(v) if (rty(v) >= 2) 0 else if (is.list(v)) sum(vapply(unclass(v), rn, 0)) else sum(is.na(v))
# every summary of one object, as cases (i, 0): `pre` is "" for the objects proper and "x" for the hand-built ones
summ <- function(i, v, pre = "") {
  a <- c(i, 0)
  add(paste0(pre, "len"), a, length(v)); add(paste0(pre, "sum"), a, rs(v)); add(paste0(pre, "wsum"), a, rw(v)); add(paste0(pre, "nna"), a, rn(v))
  add(paste0(pre, "ty"), a, rty(v)); add(paste0(pre, "isum"), a, ri(v))
  lv <- levels(v); add(paste0(pre, "nlev"), a, length(lv)); add(paste0(pre, "levs"), a, if (length(lv)) sum(vapply(lv, cu, 0)) else 0)
  d <- attr(v, "dim"); add(paste0(pre, "ndim"), a, length(d)); add(paste0(pre, "dimprod"), a, if (is.null(d)) 0 else prod(d))
  add(paste0(pre, "nnames"), a, length(names(v))); add(paste0(pre, "elh"), a, hasht(names(v)))
}
# objects the writer builds by hand: SP(mode, ...) a language mode over named or unnamed elements, SC(mode, strings) a name or missing, SY a name element,
# SK(code) an object of a code R does not know, SS(list) a structure of arbitrary members
SP <- function(mode, ...) structure(list(mode = mode, kids = list(...)), class = "spec")
SC <- function(mode, x) structure(list(mode = mode, chars = x), class = "spec")
SY <- structure(list(sym = TRUE), class = "spec")
SK <- function(code) structure(list(rawcode = code), class = "spec")
SS <- function(...) structure(list(members = list(...)), class = "spec")
encspec <- function(v, pos) {
  if (!is.null(v$sym)) return(list(code = 0, len = 0, raw = raw(0)))
  if (!is.null(v$rawcode)) return(list(code = v$rawcode, len = 0, raw = raw(0)))
  if (!is.null(v$members)) return(encs(v$members, pos))
  code <- 256 + match(v$mode, foreign:::SModeNames)
  if (!is.null(v$chars)) return(list(code = code, len = length(v$chars), raw = strs(v$chars)))
  list(code = code, len = length(v$kids), raw = encl(v$kids, pos))
}
BE <- FALSE
i32 <- function(x) writeBin(as.integer(x), raw(), size = 4, endian = if (BE) "big" else "little")
strs <- function(x) { b <- unlist(lapply(x, function(s) c(charToRaw(s), as.raw(0)))); c(i32(length(b)), b) }
# enc(v, pos): list(code, len, raw) for v whose data starts at absolute byte pos
enc <- function(v, pos) {
  if (inherits(v, "spec")) return(encspec(v, pos))
  if (is.complex(v)) return(list(code = 7, len = length(v), raw = writeBin(as.vector(rbind(Re(v), Im(v))), raw(), size = 8, endian = if (BE) "big" else "little")))
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
  summ(i, r)
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
# a top-level code of exactly 65535 is in range in either byte order: R answers with the string "Unrecognized S mode 65535 not supported"
# hand-built objects (sbin_e<k>.bin, k from 5): "eerr" is 1 when read.S stops, else the "x" summaries
nk <- 4
hand <- function(v, be) {
  BE <<- be
  nk <<- nk + 1
  path <- file.path(root, sprintf("tests/oracle/data/sbin_e%d.bin", nk))
  if (inherits(v, "raw")) writeBin(c(as.raw(c(0, 83, 32, 100, 97, 116, 97, 1)), i32(65535), i32(1), i32(0)), path) else writeS(path, v)
  res <- tryCatch(list(TRUE, suppressWarnings(read.S(path))), error = function(err) list(FALSE, NULL))
  if (!res[[1]]) add("eerr", c(nk, 0), 1) else { add("eerr", c(nk, 0), 0); summ(nk, res[[2]], "x") }
}
n1 <- 1; n2 <- c(NA, 2.5, -3)
objs <- list(
  raw(0), raw(0),
  c(1+2i, NA, 3-1i, complex(real = NA, imaginary = 2), -2.5+1e3i), complex(0), 4i,
  SC("name", c("foo", "bar")), SC("name", character(0)), SC("name", ""), SC("name", "a"), SC("name", c("", "b")),
  SC("missing", "x"), SC("missing", character(0)),
  SP("function", a = 1, 3), SP("function", 1, 3), SP("function"), SP("function", x = 5), SP("function", a = 1, b = "z", list(1, 2)),
  SP("if", 1, 2), SP("(", 3), SP("{"), SP("<-", a = 1, 2), SP("while", n2, "s"),
  SP("call(...)", 1, 2), SP("call(...)"), SP("call(...)", SP("comment"), 3), SP("call(...)", list(a = 1)),
  SP("internal", 1), SP("internal"), SP("internal", SP("comment")),
  SP("comment", 1), SP("comment.expression", SP("comment"), 3, 4), SP("comment.expression"), SP("comment.expression", SP("comment")),
  SP("expression", 1, 2, SP("comment"), 4), SP("expression"), SP("expression", a = 1, 2),
  SP("call", 1, 2), SP("call"), SP("call", SP("comment")), SP("call", a = 1, 2),
  SP("vector", 1), SP("string", 1), SP("unknown", 1), SP("[", 1), SP(" ", 1), SP("addop"), SP("end.of.file", 1),
  list(a = SY, b = 2), list(SY, 2), list(SP("comment"), 2), list(a = SP("comment"), b = 2, 3), list(1, SP("comment"), 3, d = 4),
  list(f = SP("function", x = 1, 2), c = SP("if", 1), z = c(1+1i, 2i), s = SC("name", "w"), e = SP("expression", 1)),
  SK(9), SK(0), SK(322), SK(8), list(SK(9), 2), list(a = SK(30), SK(0)),
  SS(.Data = c(1, 2, 3), .Tsp = c(1, 3, 1)), SS(.Data = c(1, 2, 3, 4), .Dim = c(2L, 2L), .Tsp = 1),
  SS(.Data = c(1+1i, 2i)), SS(.Data = SP("comment"))
)
for (j in seq_along(objs)) hand(objs[[j]], j %% 2 == 0)
emit("foreign_sbin", "foreign", list(cases))

