# ggsci continuous palettes: rgb_gsea, rgb_material, rgb_tw3 (colorRamp in Lab space with a spline).
#   args: (n, k, alpha, m, raw colours packed r * 65536 + g * 256 + b [m])  -> the k-th (0-based) of n colours packed r * 2^24 + g * 2^16 + b * 2^8 + a
suppressMessages(library(ggsci))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("ramp", args, want, rel = 0, abs = 0)
pack <- function(h) { v <- col2rgb(h, alpha = TRUE); as.numeric(v[1, ]) * 2^24 + v[2, ] * 2^16 + v[3, ] * 2^8 + v[4, ] }
pk <- function(h) { v <- col2rgb(h); as.numeric(v[1, ]) * 65536 + v[2, ] * 256 + v[3, ] }
db <- ggsci:::ggsci_db
sets <- c(list(list("gsea", db$gsea[["default"]], function(n, al) rgb_gsea("default", n, al))),
          lapply(names(db$material), function(p) list("material", db$material[[p]], function(n, al) rgb_material(p, n, al))),
          lapply(names(db$tw3), function(p) list("tw3", db$tw3[[p]], function(n, al) rgb_tw3(p, n, al))))
ri <- 0
for (s in sets) {
  raw <- s[[2]]; ri <- ri + 1; for (n in c(2, 5, 12, 20)) for (al in c(1, 0.5)) {
    cc <- s[[3]](n, al)
    for (k in seq_len(n)) { add(c(n, k - 1, al, length(raw), pk(raw)), pack(cc[k])); cases[[length(cases) + 1]] <- case("row", c(n, k - 1, al, ri), pack(cc[k]), rel = 0, abs = 0) }
  }
}
emit("labramp", "ggsci", list(cases))
