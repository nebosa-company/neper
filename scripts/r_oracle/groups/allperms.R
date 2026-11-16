# permute::allPerms for free, series and mirrored series designs, alone and within blocks.
#   args: (kind 0 free 1 series 2 mirror, nb, sizes[nb])  fn "rows", "sum", "w" (position-weighted sum, row-major)
suppressMessages(library(permute))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-12, abs = 1e-12)
designs <- list(c(3), c(4), c(5), c(6), c(7), c(2, 3), c(3, 3), c(2, 2, 2), c(3, 2, 2), c(4, 3))
for (sz in designs) for (kind in 0:2) {
  if (kind == 0 && sum(sz) > 7) next
  if (kind > 0 && length(sz) == 1 && sz[1] < 3) next
  w <- Within(type = c("free", "series", "series")[kind + 1], mirror = kind == 2)
  h <- if (length(sz) == 1) how(within = w) else how(within = w, blocks = factor(rep(seq_along(sz), sz)))
  p <- tryCatch(suppressMessages(allPerms(sum(sz), control = h)), error = function(e) NULL)
  if (is.null(p)) next
  v <- as.vector(t(p)); a <- c(kind, length(sz), sz)
  add("rows", a, nrow(p)); add("sum", a, sum(v)); add("w", a, sum(seq_along(v) * v))
}
emit("allperms", "permute", list(cases))
