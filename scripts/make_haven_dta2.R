# Writes the second set of Stata test files of tests/data/haven:
#   w<N>.dta   haven::write_dta, Stata versions 8 (format 113), 10 (114), 12 (115), 13 (117), 14 (118), 15 (119):
#              tagged missing values, labelled columns with tagged labels, UTF-8 text, strLs (13 and later)
#   h<fmt><o>.dta  built here from the format description (haven cannot write them): formats 104 to 116, byte order
#              L or M, every storage type (byte, int, long, float, double, string) with its missing codes
suppressMessages(library(haven))
dir <- "tests/data/haven"

# ---- haven written ----
set.seed(5); n <- 30
d <- data.frame(id = 1:n)
d$xv <- round(rnorm(n), 4)
d$xv[c(3, 9, 17, 25)] <- c(tagged_na("a"), tagged_na("b"), tagged_na("z"), NA)
d$yv <- as.numeric(sample(1:5, n, TRUE)); d$yv[c(2, 11)] <- c(tagged_na("c"), tagged_na("q"))
d$lab <- labelled(c(rep(1:3, length.out = n - 2), NA, tagged_na("a")), labels = c(one = 1, two = 2, three = 3, miss_a = tagged_na("a"), miss_x = tagged_na("x")), label = "Labelled with tags")
d$sv <- c("café", "", "a longer text for the string", rep(c("x", "yy y", "über"), length.out = n - 3))
d$big <- as.numeric(sample(c(1e30, -1e30, 3.5e-30, 2^40, 0, NA), n, TRUE))
d$ints <- as.integer(sample(c(-2147483000L, 2147483000L, 0L, 5L, NA), n, TRUE))
d$flag <- c(TRUE, FALSE, rep(NA, 2), rep(TRUE, n - 4))
d$longtxt <- vapply(seq_len(n), function(i) paste(rep(letters[(i %% 26) + 1], 3 + (i * 37) %% 90), collapse = ""), "")
attr(d$xv, "label") <- "A tagged number"
attr(d$sv, "label") <- "Some text"
for (v in c(8, 10, 12, 13, 14, 15)) {
  dd <- d
  write_dta(dd, file.path(dir, sprintf("w%d.dta", v)), version = v, label = "Second test data", strl_threshold = 40)
}

# ---- built here ----
u16 <- function(x, big) writeBin(as.integer(x), raw(), size = 2, endian = if (big) "big" else "little")
i32 <- function(x, big) writeBin(as.integer(x), raw(), size = 4, endian = if (big) "big" else "little")
u32 <- function(x, big) i32(ifelse(x >= 2^31, x - 2^32, x), big)
pad <- function(s, w) { b <- charToRaw(s); stopifnot(length(b) <= w); c(b, raw(w - length(b))) }
letter <- function(s) utf8ToInt(substr(s, 2, 2)) - 96   # ".a" -> 1
enc <- function(ty, v, ver, big, w = 0) {
  new <- ver >= 113
  endian <- if (big) "big" else "little"
  if (ty == "s") return(pad(v, w))
  if (is.character(v)) {   # a missing code
    k <- if (v == ".") 0 else letter(v)
    if (!new && k > 0) stop("tagged missing below 113")
    if (ty == "b") return(as.raw((if (new) 101 else 127) + k))
    if (ty == "i") return(writeBin(as.integer((if (new) 32741 else 32767) + k), raw(), size = 2, endian = endian))
    if (ty == "l") return(writeBin(as.integer((if (new) 2147483621 else 2147483647) + k), raw(), size = 4, endian = endian))
    if (ty == "f") return(i32(2130706432 + (if (k > 0) 2048 * k else 0), big))
    hi <- 2145386496 + 256 * k; lo <- 0   # 0x7FE00000 + (k << 40) >> 32
    return(if (big) c(u32(hi, TRUE), u32(lo, TRUE)) else c(u32(lo, FALSE), u32(hi, FALSE)))
  }
  if (ty == "b") return(writeBin(as.integer(v), raw(), size = 1))
  if (ty == "i") return(writeBin(as.integer(v), raw(), size = 2, endian = endian))
  if (ty == "l") return(writeBin(as.integer(v), raw(), size = 4, endian = endian))
  if (ty == "f") return(writeBin(as.numeric(v), raw(), size = 4, endian = endian))
  writeBin(as.numeric(v), raw(), size = 8, endian = endian)
}
tcode <- function(ty, ver, w = 0) {
  if (ty == "s") return(if (ver >= 111) w else 127 + w)
  if (ver >= 111) return(c(b = 251, i = 252, l = 253, f = 254, d = 255)[[ty]])
  c(b = 98, i = 105, l = 108, f = 102, d = 100)[[ty]]
}
build <- function(ver, big, cols, nobs, tables) {
  lablen <- if (ver >= 108) 81 else 32; nw <- if (ver >= 110) 33 else 9
  fw <- if (ver >= 114) 49 else if (ver >= 105) 12 else 7
  out <- c(as.raw(c(ver, if (big) 1 else 2, 1, 0)), u16(length(cols), big), u32(nobs, big))
  out <- c(out, pad("Built by hand", lablen)); if (ver >= 105) out <- c(out, pad("21 Nov 2026 12:00", 18))
  out <- c(out, as.raw(sapply(cols, function(cc) tcode(cc$ty, ver, cc$w))))
  for (cc in cols) out <- c(out, pad(cc$name, nw))
  out <- c(out, raw(2 * (length(cols) + 1)))
  for (cc in cols) out <- c(out, pad(cc$fmt, fw))
  for (cc in cols) out <- c(out, pad(cc$vl, nw))
  for (cc in cols) out <- c(out, pad(cc$label, lablen))
  if (ver >= 105) {   # one characteristic, then the end
    note <- c(pad("_dta", nw), pad("note1", nw), charToRaw("a note"), as.raw(0))
    el <- if (ver >= 110) 4 else 2
    lenb <- if (el == 4) u32(length(note), big) else u16(length(note), big)
    out <- c(out, as.raw(1), lenb, note, as.raw(0), raw(el))
  }
  for (r in seq_len(nobs)) for (cc in cols) out <- c(out, enc(cc$ty, cc$v[[r]], ver, big, cc$w))
  for (tb in tables) {
    n <- length(tb$text)
    if (ver < 105) {
      out <- c(out, u16(8 * n, big), pad(tb$name, 12), raw(2)); for (j in seq_len(n)) out <- c(out, pad(tb$text[j], 8))
    } else {
      off <- cumsum(c(0, nchar(tb$text, "bytes") + 1))[seq_len(n)]
      txt <- unlist(lapply(tb$text, function(s) c(charToRaw(s), as.raw(0))))
      vals <- do.call(c, lapply(tb$code, function(v) enc("l", v, ver, big)))
      body <- c(u32(n, big), u32(length(txt), big), do.call(c, lapply(off, u32, big = big)), vals, txt)
      out <- c(out, u32(length(body), big), pad(tb$name, 33), raw(3), body)
    }
  }
  out
}
mk <- function(ver, big, path) {
  nobs <- 9
  miss <- if (ver >= 113) c(".", ".a", ".b", ".z") else "."
  cyc <- function(vals) { v <- c(vals, as.list(miss)); lapply(seq_len(nobs), function(i) v[[(i - 1) %% length(v) + 1]]) }
  cols <- list(
    list(name = "vb", ty = "b", fmt = "%8.0g", vl = "", label = "a byte", v = cyc(list(-127, 0, 1, if (ver >= 113) 100 else 126))),
    list(name = "vi", ty = "i", fmt = "%8.0g", vl = "lab", label = "an int", v = cyc(list(-32767, 0, 7, if (ver >= 113) 32740 else 32766))),
    list(name = "vl", ty = "l", fmt = "%12.0g", vl = "", label = "a long", v = cyc(list(-2147483647, 0, 99, if (ver >= 113) 2147483620 else 2147483646))),
    list(name = "vf", ty = "f", fmt = "%9.2f", vl = "", label = "a float", v = cyc(list(0.5, -1.25, 1e30, 1.5e-30))),
    list(name = "vd", ty = "d", fmt = "%10.0g", vl = "", label = "a double", v = cyc(list(pi, -1e300, 0, 1e-300, 8.9e307))),
    list(name = "vs", ty = "s", w = 6, fmt = "%6s", vl = "", label = "a string", v = lapply(seq_len(nobs), function(i) c("abc", "", "a b c", "caf\xe9", "\x80x")[(i - 1) %% 5 + 1]))
  )
  codes <- if (ver >= 113) list(-5, 0, 7, 32740, ".", ".a", ".c") else list(-5, 0, 7)
  tables <- list(list(name = "lab", code = codes, text = paste("label", seq_along(codes))))
  if (ver < 105) tables[[1]]$code <- NULL
  writeBin(build(ver, big, cols, nobs, tables), file.path(dir, path))
}
for (ver in c(104, 105, 108, 110, 111, 112, 113, 114, 115, 116)) {
  mk(ver, FALSE, sprintf("h%dL.dta", ver))
  mk(ver, TRUE, sprintf("h%dM.dta", ver))
}
