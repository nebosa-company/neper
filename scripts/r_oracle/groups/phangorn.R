# phangorn::parsimony (Fitch) of a random binary tree and DNA alignment with ambiguity codes: "fitch" args (nt, ns, ne, parent[ne], child[ne] (0-based, ape cladewise order), data[nt * ns] row-major bit masks A 1 C 2 G 4 T 8)
suppressMessages({library(ape); library(phangorn)})
cases <- list()
set.seed(20271213)
codes <- c("a", "c", "g", "t"); bits <- c(a = 1, c = 2, g = 4, t = 8, n = 15, r = 5, y = 10, "-" = 15)
for (rep in 1:40) {
  nt <- sample(4:20, 1); ns <- sample(5:60, 1)
  tr <- reorder(rtree(nt), "cladewise")
  M <- matrix(sample(codes, nt * ns, TRUE), nt, ns, dimnames = list(tr$tip.label, NULL))
  amb <- sample(length(M), max(1, length(M) %/% 25)); M[amb] <- sample(c("n", "r", "y"), length(amb), TRUE)
  d <- phyDat(M, type = "DNA")
  sc <- as.numeric(parsimony(tr, d, method = "fitch"))
  B <- matrix(bits[as.vector(t(M))], nt, ns, byrow = TRUE)
  cases[[length(cases) + 1]] <- case("fitch", c(nt, ns, nrow(tr$edge), tr$edge[, 1] - 1, tr$edge[, 2] - 1, as.vector(t(matrix(bits[M], nt, ns)))), sc, rel = 0, abs = 1e-9)
}
# upgma and wpgma ("upg": which 0 upgma 1 wpgma, n, k, dist[n * n]) k 0 .. n - 2 the merge heights in merge order, n - 1 the total edge length
for (rep in 1:30) {
  n <- sample(4:14, 1); m <- matrix(round(runif(n * n, 1, 10), 4), n, n); m <- (m + t(m)) / 2; diag(m) <- 0; rownames(m) <- colnames(m) <- paste0("t", 1:n)
  for (w in 0:1) {
    tr <- if (w == 0) upgma(as.dist(m)) else wpgma(as.dist(m))
    v <- c(sort(branching.times(tr)), sum(tr$edge.length))
    for (k in seq_along(v)) cases[[length(cases) + 1]] <- case("upg", c(w, n, k - 1, as.vector(m)), as.numeric(v[k]), rel = 1e-9, abs = 1e-11)
  }
}
emit("phangorn", "phangorn", list(cases))
