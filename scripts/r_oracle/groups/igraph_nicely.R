# igraph layout_nicely on graphs under 1000 vertices and, from 1000 vertices, layout_with_drl; before that: layout_as_tree for a forest of up to 30 vertices, otherwise layout_with_fr followed by align_layout.
# A layout is summarised as the sum and the row-weighted sum of each coordinate column.
#   fn "nicely_<x|y><s|w>"; args: (seed, n, ne, directed, edges (0-based) [2*ne])
suppressMessages(library(igraph))
cases <- list()
add <- function(fn, args, want, tol) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = tol, abs = tol / 10)
set.seed(20261123)
sd <- 7000
for (rep in 1:50) {
  n <- sample(4:45, 1); kind <- rep %% 5
  g <- switch(kind + 1,
    sample_gnp(n, runif(1, 0.05, 0.3)),
    sample_gnp(n, runif(1, 0.05, 0.2), directed = TRUE),
    sample_pa(n, m = 1, directed = FALSE),
    sample_pa(n, m = 1, directed = TRUE),
    sample_gnp(n, runif(1, 0.01, 0.1)))
  if (ecount(g) == 0) next
  sd <- sd + 1; e <- as_edgelist(g, names = FALSE) - 1
  hdr <- c(sd, n, nrow(e), is_directed(g), as.vector(t(e)))
  set.seed(sd); m <- layout_nicely(g)
  for (k in 1:2) {
    col <- c("x", "y")[k]
    add(paste0("nicely_", col, "s"), hdr, sum(m[, k]), 1e-9); add(paste0("nicely_", col, "w"), hdr, sum(seq_len(n) * m[, k]), 1e-9)
  }
}
for (rep in 1:2) {
  n <- c(1000, 1100)[rep]; g <- sample_gnp(n, c(2, 3)[rep] / n, directed = rep == 2)
  if (ecount(g) == 0) next
  sd <- sd + 1; e <- as_edgelist(g, names = FALSE) - 1
  hdr <- c(sd, n, nrow(e), is_directed(g), as.vector(t(e)))
  set.seed(sd); m <- layout_nicely(g)
  add("nicely_xs", hdr, sum(m[, 1]), 1e-9); add("nicely_yw", hdr, sum(seq_len(n) * m[, 2]), 1e-9)
}
emit("igraph_nicely", "igraph", list(cases))
