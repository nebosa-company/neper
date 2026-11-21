# igraph layout_as_tree (Reingold-Tilford): default root choice, explicit roots with rootlevel, directed modes out / in / all, circular, flip.y.
# A layout is summarised as the sum and the row-weighted sum of each coordinate column.
#   fn "tree_<x|y><s|w>"; args: (n, ne, directed, mode 1 out 2 in 3 all, circular, flip, nroots, nlevels, roots (0-based) [nroots], levels [nlevels], edges (0-based) [2*ne])
suppressMessages(library(igraph))
cases <- list()
add <- function(fn, args, want, tol) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = tol, abs = tol / 10)
lay <- function(g, mode, circ, flip, roots, lev) {
  n <- vcount(g); e <- as_edgelist(g, names = FALSE) - 1; ne <- nrow(e)
  hdr <- c(n, ne, is_directed(g), mode, circ, flip, length(roots), length(lev), roots - 1, lev, as.vector(t(e)))
  m <- layout_as_tree(g, root = if (length(roots)) roots else numeric(), circular = circ, rootlevel = if (length(lev)) lev else numeric(), mode = c("out", "in", "all")[mode], flip.y = flip)
  for (k in 1:2) {
    col <- c("x", "y")[k]
    add(paste0("tree_", col, "s"), hdr, sum(m[, k]), 1e-9); add(paste0("tree_", col, "w"), hdr, sum(seq_len(n) * m[, k]), 1e-9)
  }
}
set.seed(20261122)
for (rep in 1:60) {
  n <- sample(4:30, 1); kind <- rep %% 6
  g <- switch(kind + 1,
    sample_gnp(n, runif(1, 0.08, 0.3)),
    sample_pa(n, m = 1, directed = FALSE),
    sample_pa(n, m = 1, directed = TRUE),
    sample_gnp(n, runif(1, 0.05, 0.2), directed = TRUE),
    { a <- sample(2:max(2, n - 2), 1); disjoint_union(sample_tree(a, directed = FALSE), sample_tree(max(2, n - a), directed = FALSE)) }, sample_tree(n, directed = FALSE))
  if (ecount(g) == 0) next
  mode <- if (is_directed(g)) sample(1:3, 1) else 1
  roots <- integer(); lev <- numeric()
  if (rep %% 5 == 0) roots <- sample(n, 1)
  if (rep %% 10 == 0) { roots <- sample(n, min(n, 3)); if (rep %% 20 == 0) lev <- sample(0:2, length(roots), replace = TRUE) }
  lay(g, mode, rep %% 7 == 0, rep %% 4 != 0, roots, lev)
}
# 500 vertices or more: root choice by eccentricity
for (rep in 1:10) {
  n <- sample(500:540, 1); kind <- rep %% 5
  g <- switch(kind + 1,
    sample_tree(n, directed = FALSE), sample_pa(n, m = 1, directed = FALSE), sample_gnp(n, 1.5 / n),
    sample_pa(n, m = 1, directed = TRUE), sample_gnp(n, 1.2 / n, directed = TRUE))
  if (ecount(g) == 0) next
  mode <- if (is_directed(g)) sample(1:3, 1) else 1
  lay(g, mode, FALSE, TRUE, integer(), numeric())
}
emit("igraph_tree", "igraph", list(cases))
