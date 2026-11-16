# igraph: transitivity, coreness, degree assortativity, similarity, eccentricity, radius, diameter of a simple undirected graph.
#   args: (n, adjacency row-major[n*n])  fn "trans_g" "trans_avg" "trans_sum" "trans_w" "core_sum" "core_w" "assort" "jac_sum" "jac_w" "dice_sum" "dice_w" "ecc_sum" "ecc_w" "radius" "diameter"
suppressMessages(library(igraph))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-10)
set.seed(20261116)
for (rep in 1:40) {
  n <- sample(6:14, 1); g <- sample_gnp(n, runif(1, 0.2, 0.6))
  if (ecount(g) < 3) next
  A <- as.matrix(as_adjacency_matrix(g)); a <- c(n, as.vector(t(A)))
  tl <- transitivity(g, "localundirected", isolates = "zero")
  add("trans_g", a, transitivity(g, "globalundirected")); add("trans_avg", a, transitivity(g, "average", isolates = "zero"))
  add("trans_sum", a, sum(tl)); add("trans_w", a, sum(seq_len(n) * tl))
  cr <- coreness(g); add("core_sum", a, sum(cr)); add("core_w", a, sum(seq_len(n) * cr))
  as_ <- assortativity_degree(g, directed = FALSE); if (is.finite(as_)) add("assort", a, as_)
  for (m in c("jaccard", "dice")) {
    S <- similarity(g, method = m); idx <- which(upper.tri(S), arr.ind = TRUE); idx <- idx[order(idx[, 1], idx[, 2]), , drop = FALSE]
    w <- (idx[, 1] - 1) * n + idx[, 2]; v <- S[idx]
    add(paste0(substr(m, 1, 3), "_sum"), a, sum(v)); add(paste0(substr(m, 1, 3), "_w"), a, sum(w * v))
  }
  e <- eccentricity(g); add("ecc_sum", a, sum(e)); add("ecc_w", a, sum(seq_len(n) * e))
  add("radius", a, radius(g)); add("diameter", a, diameter(g))
}
emit("igraph", "igraph", list(cases))
