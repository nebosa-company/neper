# Writes the two BIFF5 (Excel 5 and 95) workbooks that tests/data/xls/biff5*.xls hold, so e.fmt.xls can be
# held against readxl on the format readxl's own examples do not cover: ANSI strings (code page 1252),
# LABEL cells, a BOUNDSHEET with an ANSI name, the "Book" stream, and both stream placements of a
# compound file (a regular chain, and the mini stream below the 4096-byte cutoff).
#   Rscript scripts/r_oracle/make_biff5.R
u16 <- function(x) as.raw(c(x %% 256, (x %/% 256) %% 256))
u32 <- function(x) { x <- x %% 4294967296; as.raw(c(x %% 256, (x %/% 256) %% 256, (x %/% 65536) %% 256, (x %/% 16777216) %% 256)) }
f64 <- function(x) writeBin(as.numeric(x), raw(), endian = "little")
ansi <- function(s) iconv(s, "UTF-8", "CP1252", toRaw = TRUE)[[1]]
rec <- function(id, ...) { d <- c(...); if (is.null(d)) d <- raw(0); c(u16(id), u16(length(d)), d) }

label <- function(r, c, s) { t <- ansi(s); rec(0x204, u16(r), u16(c), u16(0), u16(length(t)), t) }
number <- function(r, c, v, xf = 0) rec(0x203, u16(r), u16(c), u16(xf), f64(v))
blank <- function(r, c) rec(0x201, u16(r), u16(c), u16(0))
boolean <- function(r, c, v) rec(0x205, u16(r), u16(c), u16(0), as.raw(c(as.integer(v), 0)))
rk <- function(r, c, v) rec(0x27e, u16(r), u16(c), u16(0), u32(v * 4 + 2))

sheet_stream <- function(cells, nrow, ncol) c(
  rec(0x809, u16(0x500), u16(0x10), u16(0x1234), u16(0x07cc)),
  rec(0x200, u16(0), u16(nrow), u16(0), u16(ncol), u16(0)),
  cells, rec(0x0a))

biff5 <- function(sheets, hidden = rep(0, length(sheets))) {
  names <- names(sheets)
  body <- lapply(sheets, function(s) sheet_stream(s$cells, s$nrow, s$ncol))
  fonts <- rec(0x31, u16(200), u16(0), u16(0x7fff), u16(400), u16(0), as.raw(c(0, 0, 0, 0, 5)), ansi("Arial"))
  xfs <- c(rec(0xe0, u16(0), u16(0), u16(0xfff5), u16(0x20), as.raw(rep(0, 8))),
           rec(0xe0, u16(0), u16(14), u16(0xfff5), u16(0x20), as.raw(rep(0, 8))),
           rec(0xe0, u16(0), u16(164), u16(0xfff5), u16(0x20), as.raw(rep(0, 8))))
  fmt <- c(rec(0x41e, u16(164), as.raw(nchar("yyyy-mm-dd")), ansi("yyyy-mm-dd")))
  head <- c(rec(0x809, u16(0x500), u16(0x05), u16(0x1234), u16(0x07cc)), rec(0x42, u16(1252)), rec(0x22, u16(0)),
            fonts, fmt, xfs)
  sheet_recs <- function(offsets) unlist(lapply(seq_along(names), function(i)
    rec(0x85, u32(offsets[i]), as.raw(c(hidden[i], 0, nchar(names[i]))), ansi(names[i]))))
  glen <- length(head) + length(sheet_recs(rep(0, length(names)))) + 4
  offs <- glen + c(0, cumsum(sapply(body, length)))[seq_along(body)]
  c(head, sheet_recs(offs), rec(0x0a), unlist(body))
}

# A compound file holding one stream called `name`: 512-byte sectors, one FAT sector, one directory sector.
cfb <- function(stream, name = "Book") {
  mini <- length(stream) < 4096
  pad <- function(x, n) c(x, raw((-length(x)) %% n))
  dirent <- function(nm, type, start, size, left = -1, right = -1, child = -1) {
    u <- iconv(nm, "UTF-8", "UTF-16LE", toRaw = TRUE)[[1]]
    c(pad(u, 64), u16(length(u) + 2), as.raw(c(type, 1)), u32(left), u32(right),
      u32(child), raw(16), raw(4), raw(16), u32(start), u32(size), raw(4))
  }
  EOC <- 0xfffffffe; FREE <- 0xffffffff; FATSEC <- 0xfffffffd
  if (mini) {
    nmini <- ceiling(length(stream) / 64)
    ministream <- pad(stream, 512)           # the mini stream is stored in one or more regular sectors
    nms <- length(ministream) / 512
    # sectors: 0 FAT, 1 directory, 2 mini FAT, 3.. mini stream
    fat <- c(FATSEC, EOC, EOC, if (nms > 1) c(4:(2 + nms), EOC) else EOC)
    minifat <- c(if (nmini > 1) c(1:(nmini - 1), EOC) else EOC)
    minifat_sector <- pad(unlist(lapply(minifat, u32)), 512)
    dir <- pad(c(dirent("Root Entry", 5, 3, nmini * 64, child = 1), dirent(name, 2, 0, length(stream))), 512)
    secs <- c(pad(unlist(lapply(c(fat, rep(FREE, 128 - length(fat))), u32)), 512), dir, minifat_sector, ministream)
    minifat_start <- 2; nminifat <- 1
  } else {
    n <- ceiling(length(stream) / 512)
    # sectors: 0 FAT, 1 directory, 2.. stream
    fat <- c(FATSEC, EOC, if (n > 1) c(3:(1 + n), EOC) else EOC)
    stopifnot(length(fat) <= 128)
    dir <- pad(c(dirent("Root Entry", 5, EOC, 0, child = 1), dirent(name, 2, 2, length(stream))), 512)
    secs <- c(pad(unlist(lapply(c(fat, rep(FREE, 128 - length(fat))), u32)), 512), dir, pad(stream, 512))
    minifat_start <- EOC; nminifat <- 0
  }
  hdr <- c(as.raw(c(0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1)), raw(16), u16(0x3e), u16(3), u16(0xfffe), u16(9), u16(6), raw(6),
           u32(0), u32(1), u32(1), u32(0), u32(4096), u32(minifat_start), u32(nminifat), u32(EOC), u32(0),
           u32(0), unlist(lapply(rep(FREE, 108), u32)))
  stopifnot(length(hdr) == 512)
  c(hdr, secs)
}

root <- normalizePath(file.path(dirname(sub("--file=", "", grep("--file=", commandArgs(FALSE), value = TRUE))), "..", ".."))
out <- file.path(root, "tests", "data", "xls")
text <- c("plain", "café", "naïve Über", "€ 5", "“quoted” – dash", "  padded  ")
mk <- function(rows) {
  cells <- raw(0)
  for (r in seq_len(nrow(rows))) {
    cells <- c(cells, label(r - 1, 0, rows$t[r]), number(r - 1, 1, rows$n[r]), number(r - 1, 2, 40000 + r, xf = 1),
               if (r %% 2) boolean(r - 1, 3, r %% 3 == 0) else blank(r - 1, 3), rk(r - 1, 4, r * 3))
  }
  list(cells = cells, nrow = nrow(rows), ncol = 5)
}
small <- data.frame(t = text, n = c(1.5, -2, 3e10, 0.1, 100, 7))
set.seed(1)
big <- data.frame(t = rep(text, length.out = 150), n = round(rnorm(150), 6))
writeBin(cfb(biff5(list(Sheet1 = mk(small), `Café data` = mk(small[1:3, ])))), file.path(out, "biff5_mini.xls"))
writeBin(cfb(biff5(list(Numbers = mk(big), Second = mk(small)))), file.path(out, "biff5.xls"))
cat("wrote", file.path(out, c("biff5_mini.xls", "biff5.xls")), "\n")
