# RcppAnnoy 0.0.23: indexes built with setSeed, euclidean / angular / manhattan / hamming, getNNsByItem and getNNsByVector with search_k, getDistance,
# getItemsVector, getNTrees, and the index file (size and a checksum of every byte; for hamming the unspecified bytes Annoy leaves uninitialised in a
# split node are zeroed first). The items are an integer hash of (i, z), so Neper regenerates them; no random draws happen in R.
#
# A case is (metric 0 euclidean 1 angular 2 manhattan 3 hamming, n, f, trees (-1 = automatic), seed (-1 = default), dtype, mode, phase, qkind, qidx, N, search_k,
# kind, rank). dtype 0 hash, 1 many duplicate points, 2 hash with zero vectors; mode 0 plain, 2 build / unbuild / add 5 items / rebuild, 3 item ids with gaps.
# phase 0 is the freshly built index, 1 the index after save() (Annoy reloads it from the file), 2 a new index loaded from the file.
# qkind 0 neighbours of item qidx, 1 of a fresh vector from seed index qidx, 2 of the zero vector. kind 0: number returned, 1: item at `rank`, 2: distance at
# `rank`, 10: file size, 11: file checksum, 12: n_trees, 13: n_items, 14: getDistance(qidx, rank), 15: element `rank` of item qidx, 16: checksum of node `rank`.
library(RcppAnnoy)

fv <- function(i, z, dtype) {
  if (dtype == 1) return(((i %% 4) + z) / 2)
  if (dtype == 2 && i %% 17 == 5) return(0)
  b <- (i * 7919 + z * 104729 + ((i * z * 31 + i * i * 13 + z * z * 7) %% 997) * 17) %% 2003
  (b - 1001) / 8
}
hw <- function(i, z, k) ((i + 1) * (z * 131 + k * 7 + 17) * 2654435 + i * z * 977 + k * 12345)
hv <- function(i, z, dtype) {
  if (dtype == 1) return((i %% 4) * 1234567 + z)
  (hw(i, z, 0) %% 67108864) * 134217728 + hw(i, z, 1) %% 134217728
}
item_vec <- function(metric, i, f, dtype) {
  if (metric == 3) sapply(0:(f - 1), function(z) hv(i, z, dtype)) else sapply(0:(f - 1), function(z) fv(i, z, dtype))
}
u32 <- function(b, at) sum(b[at + 1:4] * c(1, 256, 65536, 16777216))

hash_bytes <- function(b) {
  h <- 0
  for (x in b) h <- (h * 257 + x + 1) %% 2147483647
  h
}
canon <- function(b, s, K, nnodes) {
  for (node in 0:(nnodes - 1)) {
    base <- node * s
    if (u32(b, base) > K) {
      b[base + 12 + 1:4] <- 0
      if (s > 24) b[(base + 24 + 1):(base + s)] <- 0
    }
  }
  b
}

emit_cases <- list()
add <- function(head, kind, rank, want, rel = 0, abs = 0, qk = 0, qi = 0, N = 0, sk = 0) {
  head[9:12] <- c(qk, qi, N, sk)
  emit_cases[[length(emit_cases) + 1]] <<- case("annoy", c(head, kind, rank), want, rel, abs)
}

run_scenario <- function(metric, n, f, trees, seed, dtype, mode) {
  cls <- switch(metric + 1, AnnoyEuclidean, AnnoyAngular, AnnoyManhattan, AnnoyHamming)
  s <- switch(metric + 1, 16 + 4 * f, 12 + 4 * f, 16 + 4 * f, 16 + 8 * f)
  K <- switch(metric + 1, f + 2, f + 2, f + 2, 3 + 2 * f)
  ids <- 0:(n - 1)
  if (mode == 3) ids <- ids[ids %% 5 != 3]
  make <- function() {
    a <- new(cls, f)
    if (seed >= 0) a$setSeed(seed)
    for (i in ids) a$addItem(i, item_vec(metric, i, f, dtype))
    a$build(trees)
    if (mode == 2) {
      a$unbuild()
      for (i in n:(n + 4)) a$addItem(i, item_vec(metric, i, f, dtype))
      a$build(trees)
    }
    a
  }
  all_ids <- ids
  if (mode == 2) all_ids <- c(ids, n:(n + 4))
  first <- all_ids[1]; mid <- all_ids[length(all_ids) %/% 2]; last <- all_ids[length(all_ids)]
  qs <- list(c(0, first, 10, -1), c(0, mid, 5, 50), c(0, last, 15, -1), c(1, 0, 10, -1), c(1, 1, 5, 200), c(1, 2, 20, -1), c(1, 3, 10, 7))
  if (dtype == 2) qs[[length(qs) + 1]] <- c(2, 0, 5, -1)
  head <- c(metric, n, f, trees, seed, dtype, mode, 0, 0, 0, 0, 0)
  qvec <- function(q) {
    if (q[1] == 0) return(NULL)
    if (q[1] == 2) return(rep(0, f))
    item_vec(metric, n + 13 + q[2], f, dtype)
  }
  query <- function(a, q) {
    if (q[1] == 0) a$getNNsByItemList(q[2], q[3], q[4], TRUE) else a$getNNsByVectorList(qvec(q), q[3], q[4], TRUE)
  }
  report <- function(a, phase, nq) {
    h <- head; h[8] <- phase
    add(h, 12, 0, a$getNTrees())
    add(h, 13, 0, a$getNItems())
    for (q in qs[seq_len(nq)]) {
      r <- query(a, q)
      add(h, 0, 0, length(r$item), qk = q[1], qi = q[2], N = q[3], sk = q[4])
      for (k in seq_along(r$item)) {
        add(h, 1, k - 1, r$item[k], qk = q[1], qi = q[2], N = q[3], sk = q[4])
        add(h, 2, k - 1, r$distance[k], qk = q[1], qi = q[2], N = q[3], sk = q[4])
      }
    }
  }
  a <- make()
  report(a, 0, length(qs))
  pr <- c(first, mid, last)
  h <- head; h[8] <- 0
  for (i in pr) for (j in pr) add(h, 14, j, a$getDistance(i, j), qi = i)
  for (i in pr) {
    v <- a$getItemsVector(i)
    for (z in seq_len(f)) add(h, 15, z - 1, v[z], qi = i)
  }
  tf <- tempfile()
  a$save(tf)
  b <- as.integer(readBin(tf, "raw", file.size(tf)))
  nn <- length(b) / s
  if (metric == 3) b <- canon(b, s, K, nn)
  add(h, 10, 0, length(b))
  add(h, 11, 0, hash_bytes(b))
  if (nn <= 120) for (node in 0:(nn - 1)) add(h, 16, node, hash_bytes(b[node * s + 1:s]))
  report(a, 1, 3)
  c2 <- new(cls, f)
  c2$load(tf)
  report(c2, 2, 3)
}

scenarios <- list(
  c(0, 5, 4, 2, 3, 0, 0), c(0, 40, 3, 3, 7, 0, 0), c(0, 200, 8, 10, 42, 0, 0), c(0, 400, 12, -1, 123, 0, 0),
  c(0, 120, 2, 5, 1, 1, 0), c(0, 150, 6, 8, 99, 0, 2), c(0, 100, 5, 6, 5, 0, 3), c(0, 60, 4, 4, -1, 0, 0),
  c(1, 5, 4, 2, 3, 0, 0), c(1, 40, 3, 3, 7, 0, 0), c(1, 200, 8, 10, 42, 2, 0), c(1, 400, 12, -1, 123, 0, 0),
  c(1, 120, 2, 5, 1, 1, 0), c(1, 150, 6, 8, 99, 0, 2), c(1, 100, 5, 6, 5, 0, 3), c(1, 60, 4, 4, -1, 2, 0),
  c(2, 5, 4, 2, 3, 0, 0), c(2, 40, 3, 3, 7, 0, 0), c(2, 200, 8, 10, 42, 0, 0), c(2, 400, 12, -1, 123, 0, 0),
  c(2, 120, 2, 5, 1, 1, 0), c(2, 150, 6, 8, 99, 0, 2), c(2, 100, 5, 6, 5, 0, 3),
  c(3, 5, 1, 2, 3, 0, 0), c(3, 40, 1, 3, 7, 0, 0), c(3, 200, 2, 10, 42, 0, 0), c(3, 300, 4, -1, 123, 0, 0),
  c(3, 100, 2, 5, 1, 1, 0), c(3, 100, 3, 6, 5, 0, 3), c(3, 60, 1, 4, -1, 2, 0)
)
for (sc in scenarios) do.call(run_scenario, as.list(sc))
emit("annoy", "RcppAnnoy", list(emit_cases))
