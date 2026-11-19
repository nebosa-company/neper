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
# dist.hamming and the Jukes-Cantor dist.ml of unambiguous DNA ("ham": which 0 hamming 1 JC69, nt, ns, i, j, data row-major bit masks)
for (rep in 1:25) {
  nt <- sample(3:10, 1); ns <- sample(30:150, 1)
  M <- matrix(sample(codes, nt * ns, TRUE), nt, ns, dimnames = list(paste0("t", 1:nt), NULL)); d <- phyDat(M, type = "DNA")
  dh <- as.matrix(dist.hamming(d)); dj <- as.matrix(dist.ml(d, model = "JC69"))
  Bm <- as.vector(t(matrix(bits[M], nt, ns)))
  for (i in 1:(nt - 1)) for (j in (i + 1):nt) {
    cases[[length(cases) + 1]] <- case("hamd", c(0, nt, ns, i - 1, j - 1, Bm), dh[i, j], rel = 1e-9, abs = 1e-11)
    cases[[length(cases) + 1]] <- case("hamd", c(1, nt, ns, i - 1, j - 1, Bm), dj[i, j], rel = 1e-4, abs = 1e-6)
  }
}
# Sankoff parsimony with a random symmetric cost matrix ("sank": nt, ns, ne, parent, child, cost[16] row-major, data row-major bit masks); the trees may have multifurcations
for (rep in 1:30) {
  nt <- sample(4:15, 1); ns <- sample(5:50, 1)
  tr <- reorder(multi2di(rtree(nt), random = FALSE), "cladewise"); if (rep %% 3 == 0) { tr <- rtree(nt); tr <- di2multi(tr, tol = 0); tr <- reorder(tr, "cladewise") }
  Cm <- matrix(0, 4, 4); Cm[upper.tri(Cm)] <- sample(1:4, 6, TRUE); Cm <- Cm + t(Cm)
  M <- matrix(sample(codes, nt * ns, TRUE), nt, ns, dimnames = list(tr$tip.label, NULL)); d <- phyDat(M, type = "DNA")
  sc <- as.numeric(parsimony(tr, d, method = "sankoff", cost = Cm))
  cases[[length(cases) + 1]] <- case("sankoff", c(nt, ns, nrow(tr$edge), tr$edge[, 1] - 1, tr$edge[, 2] - 1, as.vector(Cm), as.vector(t(matrix(bits[M], nt, ns)))), sc, rel = 0, abs = 1e-9)
}
# pml(tree, data) log-likelihood under JC ("jcll": nt, ns, ne, parent, child, edge length, data row-major bit masks); trees binary or multifurcating
for (rep in 1:30) {
  nt <- sample(4:12, 1); ns <- sample(10:80, 1)
  tr <- reorder(rtree(nt), "cladewise"); tr$edge.length <- round(runif(nrow(tr$edge), 0.01, 0.6), 4)
  M <- matrix(sample(codes, nt * ns, TRUE), nt, ns, dimnames = list(tr$tip.label, NULL))
  amb <- sample(length(M), max(1, length(M) %/% 25)); M[amb] <- sample(c("n", "r", "y"), length(amb), TRUE)
  d <- phyDat(M, type = "DNA")
  ll <- pml(tr, d, model = "JC")$logLik
  cases[[length(cases) + 1]] <- case("jcloglik", c(nt, ns, nrow(tr$edge), tr$edge[, 1] - 1, tr$edge[, 2] - 1, tr$edge.length, as.vector(t(matrix(bits[M], nt, ns)))), as.numeric(ll), rel = 1e-9, abs = 1e-9)
}
# pml(tree, data, model = "GTR", bf, Q) log-likelihood ("gtrloglik": nt, ns, ne, parent, child, edge length, bf[4], rates[6] AC AG AT CG CT GT, data row-major bit masks)
for (rep in 1:30) {
  nt <- sample(4:12, 1); ns <- sample(10:80, 1)
  tr <- reorder(rtree(nt), "cladewise"); tr$edge.length <- round(runif(nrow(tr$edge), 0.01, 0.8), 4)
  M <- matrix(sample(codes, nt * ns, TRUE), nt, ns, dimnames = list(tr$tip.label, NULL)); d <- phyDat(M, type = "DNA")
  bf <- runif(4, 0.1, 0.5); bf <- round(bf / sum(bf), 5); bf[4] <- 1 - sum(bf[1:3]); rt <- round(runif(6, 0.3, 4), 3)
  ll <- pml(tr, d, model = "GTR", bf = bf, Q = rt)$logLik
  cases[[length(cases) + 1]] <- case("gtrloglik", c(nt, ns, nrow(tr$edge), tr$edge[, 1] - 1, tr$edge[, 2] - 1, tr$edge.length, bf, rt, as.vector(t(matrix(bits[M], nt, ns)))), as.numeric(ll), rel = 1e-8, abs = 1e-8)
}
# the same with discrete gamma rates ("gtrgamma": nt, ns, ne, parent, child, edge length, bf[4], rates[6], shape, k, data)
for (rep in 1:25) {
  nt <- sample(4:10, 1); ns <- sample(10:60, 1)
  tr <- reorder(rtree(nt), "cladewise"); tr$edge.length <- round(runif(nrow(tr$edge), 0.01, 0.8), 4)
  M <- matrix(sample(codes, nt * ns, TRUE), nt, ns, dimnames = list(tr$tip.label, NULL)); d <- phyDat(M, type = "DNA")
  bf <- runif(4, 0.1, 0.5); bf <- round(bf / sum(bf), 5); bf[4] <- 1 - sum(bf[1:3]); rt <- round(runif(6, 0.3, 4), 3)
  shape <- round(runif(1, 0.2, 4), 3); k <- sample(2:6, 1)
  ll <- pml(tr, d, model = "GTR", bf = bf, Q = rt, k = k, shape = shape)$logLik
  cases[[length(cases) + 1]] <- case("gtrgammall", c(nt, ns, nrow(tr$edge), tr$edge[, 1] - 1, tr$edge[, 2] - 1, tr$edge.length, bf, rt, shape, k, as.vector(t(matrix(bits[M], nt, ns)))), as.numeric(ll), rel = 1e-8, abs = 1e-8)
}
emit("phangorn", "phangorn", list(cases))
