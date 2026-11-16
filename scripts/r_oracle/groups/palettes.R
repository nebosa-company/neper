# ggsci and ggthemes discrete palettes against the generated table (scripts/gen_palettes.R, row order).
#   args: (row, k, alpha)  the k-th colour of the palette at that alpha as r * 2^24 + g * 2^16 + b * 2^8 + a
#   fn "size": (row) the number of colours
suppressMessages({ library(ggsci); library(ggthemes) })
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 0, abs = 0)
pack <- function(h) { v <- col2rgb(h, alpha = TRUE); as.numeric(v[1, ]) * 2^24 + v[2, ] * 2^16 + v[3, ] * 2^8 + v[4, ] }
row <- 0
for (fn in grep("^pal_", getNamespaceExports("ggsci"), value = TRUE)) {
  f <- get(fn, asNamespace("ggsci")); fm <- formals(f)
  if (!is.null(fm$n)) next
  pals <- if (!is.null(fm$palette)) eval(fm$palette) else NA
  for (p in pals) {
    pf <- tryCatch(if (is.na(p)) f() else f(palette = p), error = function(e) NULL)
    if (is.null(pf)) next
    mx <- attr(pf, "max_n"); if (is.null(mx)) mx <- 8
    cols <- tryCatch(pf(mx), error = function(e) NULL)
    if (is.null(cols) || !all(grepl("^#[0-9A-Fa-f]{6}", cols))) next
    add("size", c(row), length(cols))
    for (al in c(1, 0.3, 0.5, 0.8)) {
      pa <- if (is.na(p)) f(alpha = al) else f(palette = p, alpha = al)
      cc <- pa(mx)
      if (!identical(toupper(substr(cc, 1, 7)), toupper(substr(cols, 1, 7)))) next
      for (k in seq_along(cc)) add("colour", c(row, k - 1, al), pack(cc[k]))
    }
    row <- row + 1
  }
}
tp <- ggthemes::ggthemes_data[["tableau"]][["color-palettes"]]
for (ty in names(tp)) for (nm in names(tp[[ty]])) {
  cols <- toupper(substr(tp[[ty]][[nm]][["value"]], 1, 7))
  if (!all(grepl("^#[0-9A-F]{6}$", cols))) next
  add("size", c(row), length(cols))
  for (k in seq_along(cols)) add("colour", c(row, k - 1, 1), pack(cols[k]))
  row <- row + 1
}
emit("palettes", c("ggsci", "ggthemes"), list(cases))
