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
# triad census, mutual arcs, bridges, edge and vertex connectivity, inverse log-weighted similarity: "tri" (n, adj directed, k), "mutual", "bridges_n", "bridges_w", "econn", "vconn", "invlog_sum", "invlog_w"
for (rep in 1:30) {
  n <- sample(6:12, 1); g <- sample_gnp(n, runif(1, 0.15, 0.5), directed = TRUE)
  A <- as.matrix(as_adjacency_matrix(g)); a <- c(n, as.vector(t(A)))
  tc <- triad_census(g)
  for (k in 0:15) add("tri", c(a, k), tc[k + 1])
  add("mutual", a, sum(which_mutual(g)))
  u <- sample_gnp(n, runif(1, 0.2, 0.6)); if (ecount(u) < 2) next
  Au <- as.matrix(as_adjacency_matrix(u)); au <- c(n, as.vector(t(Au)))
  br <- bridges(u); add("bridges_n", au, length(br))
  if (length(br) > 0) { ee <- ends(u, br); add("bridges_w", au, sum(pmin(ee[, 1], ee[, 2]) * n + pmax(ee[, 1], ee[, 2]))) } else add("bridges_w", au, 0)
  add("econn", au, edge_connectivity(u)); add("vconn", au, vertex_connectivity(u))
  S <- similarity(u, method = "invlogweighted"); idx <- which(upper.tri(S), arr.ind = TRUE); idx <- idx[order(idx[, 1], idx[, 2]), , drop = FALSE]
  w <- (idx[, 1] - 1) * n + idx[, 2]; v <- S[idx]
  add("invlog_sum", au, sum(v)); add("invlog_w", au, sum(w * v))
}
# motifs(g, 3) of an undirected graph ("mot": n, adj, class 2 or 3) and dominator_tree ("dom": n, adj directed, root, v): the immediate dominator index (0-based), -1 for the root, NaN unreachable
for (rep in 1:30) {
  n <- sample(6:12, 1); u <- sample_gnp(n, runif(1, 0.2, 0.6)); Au <- as.matrix(as_adjacency_matrix(u)); au <- c(n, as.vector(t(Au)))
  mt <- motifs(u, 3); add("mot", c(au, 2), mt[3]); add("mot", c(au, 3), mt[4])
  g <- sample_gnp(n, runif(1, 0.2, 0.5), directed = TRUE); A <- as.matrix(as_adjacency_matrix(g)); a <- c(n, as.vector(t(A)))
  rt <- sample(n, 1); dm <- dominator_tree(g, rt)$dom
  for (v in 1:n) { val <- as.numeric(dm[v]); add("dom", c(a, rt - 1, v - 1), if (is.na(val) || val < 0) -1 else val - 1) }
}
emit("igraph", "igraph", list(cases))
