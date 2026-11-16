# igraph layouts: in_circle (with an order), as_star, on_grid, on_sphere. The result is summarised as the sum and
# the position-weighted sum of each coordinate column.
#   args: (n, p1, p2)  fn "<layout>_<col><s|w>": col x y z, s sum, w sum(row index * value); p1 = width / centre (1-based) / order seed
suppressMessages(library(igraph))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-10)
summ <- function(nm, m, args) for (k in seq_len(ncol(m))) {
  col <- c("x", "y", "z")[k]
  add(paste0(nm, "_", col, "s"), args, sum(m[, k])); add(paste0(nm, "_", col, "w"), args, sum(seq_len(nrow(m)) * m[, k]))
}
set.seed(20261116)
for (n in 1:16) {
  g <- make_empty_graph(n)
  summ("circle", layout_in_circle(g), c(n, 0, 0))
  ord <- sample(n); m <- layout_in_circle(g, order = ord)
  # the order is passed as its permutation index vector appended after the header
  for (k in 1:2) { col <- c("x", "y")[k]; cases[[length(cases) + 1]] <- case(paste0("circleo_", col, "s"), c(n, ord - 1), sum(m[, k]), rel = 1e-9, abs = 1e-10); cases[[length(cases) + 1]] <- case(paste0("circleo_", col, "w"), c(n, ord - 1), sum(seq_len(n) * m[, k]), rel = 1e-9, abs = 1e-10) }
  if (n >= 2) for (ce in unique(c(1, n, (n + 1) %/% 2))) summ("star", layout_as_star(g, center = ce), c(n, ce - 1, 0))
  for (w in c(0, 3, 5)) summ("grid", layout_on_grid(g, width = w), c(n, w, 0))
  if (n >= 3) summ("sphere", layout_on_sphere(g), c(n, 0, 0))
}
emit("layout", "igraph", list(cases))
