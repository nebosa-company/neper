# readxl on the .xls example workbooks in tests/data/xls: every cell of every sheet from A1, typed.
#   args: (file, sheet, row, col)   file 0 clippy 1 datasets 2 deaths 3 geometry 4 type-me; sheet, row, col 0-based
#   "xls_kind": 0 blank or error, 1 text, 2 number, 3 boolean, 4 date; "xls_num": the number, the boolean as 0 or 1, the date as a
#   serial number; "xls_text": the text (a text case); "xls_rows" and "xls_cols": the size of the sheet's table (args: file, sheet)
library(readxl)
suppressMessages(library(cellranger))
cases <- list()
add <- function(fn, args, want, ...) cases[[length(cases) + 1]] <<- case(fn, args, want, ...)
files <- c("clippy", "datasets", "deaths", "geometry", "type-me")
# 5 biff5 and 6 biff5_mini are BIFF5 workbooks written by scripts/r_oracle/make_biff5.R
cell_files <- c(files, "biff5", "biff5_mini")
for (fi in seq_along(cell_files)) {
  path <- file.path(root, "tests", "data", "xls", paste0(cell_files[fi], ".xls"))
  for (si in seq_along(excel_sheets(path))) {
    x <- suppressMessages(read_excel(path, sheet = si, range = cell_limits(c(1, 1), c(NA, NA)), col_names = FALSE, col_types = "list", na = character(), trim_ws = FALSE))
    add("xls_rows", c(fi - 1, si - 1), nrow(x), rel = 0, abs = 0)
    add("xls_cols", c(fi - 1, si - 1), ncol(x), rel = 0, abs = 0)
    for (r in seq_len(nrow(x))) for (c in seq_len(ncol(x))) {
      v <- x[[c]][[r]]
      a <- c(fi - 1, si - 1, r - 1, c - 1)
      if (inherits(v, "POSIXct")) {
        add("xls_kind", a, 4, rel = 0, abs = 0)
        add("xls_num", a, as.numeric(v) / 86400 + 25569, rel = 1e-12, abs = 2e-8)
      } else if (is.character(v)) {
        add("xls_kind", a, 1, rel = 0, abs = 0)
        cases[[length(cases) + 1]] <- case("xls_text", a, v)
      } else if (is.logical(v) && is.na(v)) {
        add("xls_kind", a, 0, rel = 0, abs = 0)
      } else if (is.logical(v)) {
        add("xls_kind", a, 3, rel = 0, abs = 0)
        add("xls_num", a, as.numeric(v), rel = 0, abs = 0)
      } else {
        add("xls_kind", a, 2, rel = 0, abs = 0)
        add("xls_num", a, v, rel = 1e-14, abs = 0)
      }
    }
  }
}
# merged ranges, from the xlsx twin of each workbook (the same sheet, the same merges): (file, sheet, i, k) with
# k 0 first row, 1 last row, 2 first column, 3 last column, sorted by first row then first column
col_index <- function(s) { v <- utf8ToInt(s) - 64; Reduce(function(a, b) a * 26 + b, v, 0) - 1 }
for (fi in seq_along(files)) {
  xl <- file.path(root, "tests", "data", "xls", paste0(files[fi], ".xlsx"))
  src <- file.path(system.file("extdata", package = "readxl"), paste0(files[fi], ".xlsx"))
  for (si in seq_along(excel_sheets(src))) {
    tmp <- tempfile(); dir.create(tmp)
    unzip(src, sprintf("xl/worksheets/sheet%d.xml", si), exdir = tmp)
    xml <- paste(readLines(file.path(tmp, sprintf("xl/worksheets/sheet%d.xml", si)), warn = FALSE), collapse = "")
    refs <- regmatches(xml, gregexpr('<mergeCell ref="[A-Z0-9:]+"', xml))[[1]]
    refs <- sub('<mergeCell ref="', "", sub('"$', "", refs))
    rects <- lapply(refs, function(r) {
      p <- strsplit(r, ":")[[1]]; if (length(p) == 1) p <- c(p, p)
      cl <- function(z) c(as.numeric(sub("^[A-Z]+", "", z)) - 1, col_index(sub("[0-9]+$", "", z)))
      a <- cl(p[1]); b <- cl(p[2]); c(a[1], b[1], a[2], b[2])
    })
    if (length(rects)) rects <- rects[order(sapply(rects, `[`, 1), sapply(rects, `[`, 3))]
    add("xls_nmerged", c(fi - 1, si - 1), length(rects), rel = 0, abs = 0)
    for (i in seq_along(rects)) for (k in 1:4) add("xls_merged", c(fi - 1, si - 1, i - 1, k - 1), rects[[i]][k], rel = 0, abs = 0)
  }
}
# hidden sheets and encryption, on byte patches of datasets.xls that the fixture applies too. BOUNDSHEET state bytes at 0-based
# offsets 11528, 11546 and 11566 (0 visible, 1 hidden, 2 very hidden); the first record after the globals BOF (INTERFACEHDR at 532)
# turned into FILEPASS with its first data byte (536) 0 for XOR and 1 for RC4. readxl lists every sheet whatever its state and
# refuses an encrypted workbook with "Unsupported encryption scheme".
raw_ds <- readBin(file.path(root, "tests", "data", "xls", "datasets.xls"), "raw", file.size(file.path(root, "tests", "data", "xls", "datasets.xls")))
vis <- c(0, 1, 2)
x <- raw_ds
for (k in 1:3) x[c(11529, 11547, 11567)[k]] <- as.raw(vis[k])
hf <- tempfile(fileext = ".xls"); writeBin(x, hf)
nm <- excel_sheets(hf)
add("xls_hidden_n", c(0), length(nm), rel = 0, abs = 0)
for (k in 1:3) {
  add("xls_hidden_state", c(k - 1), vis[k], rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("xls_hidden_name", c(k - 1), nm[k])
}
for (t in c(0, 1)) {
  x <- raw_ds; x[533] <- as.raw(0x2f); x[537] <- as.raw(t)
  ef <- tempfile(fileext = ".xls"); writeBin(x, ef)
  failed <- tryCatch({ excel_sheets(ef); 0 }, error = function(e) grepl("encryption", conditionMessage(e)))
  add("xls_encrypted", c(t), as.numeric(failed), rel = 0, abs = 0)
}
emit("xls", "readxl", list(cases))
