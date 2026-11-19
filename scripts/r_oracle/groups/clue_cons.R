# clue: cl_consensus of partitions ("SE" from a given start, "DWH" in the given order), of hclust trees ("majority"), and cl_medoid, against e.algo.stat.cluecons.
#   "se" (B, n, k, w[B], start n by k row-major, labels B by n): sum over the consensus membership of entry * (10 * row + column)
#   "dwh" (B, n, k, w[B], labels B by n): the same checksum
#   "maj" (B, n, w[B], method[B], points B by n by 2): sum over the n by n ultrametric of entry * (7 * i + 3 * j + 1), i and j 1-based
#   "medoid" (B, n, k, labels B by n): the 1-based index of cl_medoid's choice
suppressMessages(library(clue))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-9)
set.seed(20262420)
chk <- function(M, n, k) sum(M * outer(seq_len(n), seq_len(k), function(i, j) 10 * i + j))
mk <- function(lab) as.cl_partition(factor(lab))
for (rep in 1:40) {
  B <- sample(3:6, 1); n <- sample(10:30, 1); k <- sample(2:4, 1)
  labs <- t(sapply(seq_len(B), function(b) { kb <- sample(2:k, 1); c(seq_len(kb), sample(seq_len(kb), n - kb, replace = TRUE)) }))
  if (!any(apply(labs, 1, max) == k)) labs[1, 1:k] <- seq_len(k)
  # make partitions noisy copies of one base so the consensus is non trivial
  base <- c(seq_len(k), sample(seq_len(k), n - k, replace = TRUE))
  for (b in seq_len(B)) { labs[b, ] <- base; flip <- sample(n, sample(1:4, 1)); labs[b, flip] <- sample(seq_len(k), length(flip), TRUE); labs[b, ] <- as.integer(factor(labs[b, ])) }
  if (any(apply(labs, 1, function(r) length(unique(r))) < 1)) next
  w <- round(runif(B, 0.5, 3), 2)
  st <- matrix(runif(n * k), n, k); st <- st / rowSums(st)
  ens <- as.cl_ensemble(lapply(seq_len(B), function(b) mk(labs[b, ])))
  kk <- max(sapply(ens, n_of_classes))
  if (kk != k) next
  res <- cl_consensus(ens, method = "SE", weights = w, control = list(start = st))
  add("se", c(B, n, k, w, as.vector(t(st)), as.vector(t(labs))), chk(matrix(as.numeric(unclass(cl_membership(res, k))), n), n, k))
  res <- cl_consensus(ens, method = "DWH", weights = w, control = list(order = seq_len(B)))
  add("dwh", c(B, n, k, w, as.vector(t(labs))), chk(matrix(as.numeric(unclass(cl_membership(res, k))), n), n, k))
  med <- cl_medoid(ens)
  add("medoid", c(B, n, k, as.vector(t(labs))), which(sapply(ens, function(e) identical(unclass(cl_class_ids(e)), unclass(cl_class_ids(med))))) [1])
}
meth <- c("ward.D", "single", "complete", "average", "mcquitty", "median", "centroid", "ward.D2")
for (rep in 1:40) {
  B <- sample(3:6, 1); n <- sample(6:20, 1)
  x0 <- matrix(round(rnorm(n * 2) * 3, 3), n, 2); w <- round(runif(B, 0.5, 3), 2)
  mm <- sample(c(1, 2, 3, 4, 5, 8), B, TRUE)
  pts <- lapply(seq_len(B), function(b) x0 + matrix(round(rnorm(n * 2, 0, 0.5), 3), n, 2))
  hs <- lapply(seq_len(B), function(b) hclust(dist(pts[[b]]), meth[mm[b]]))
  res <- tryCatch(cl_consensus(as.cl_ensemble(hs), method = "majority", weights = w), error = function(e) NULL)
  if (is.null(res)) next
  d <- as.matrix(cl_ultrametric(res))
  add("maj", c(B, n, w, mm, unlist(lapply(pts, function(p) as.vector(t(p))))), sum(d * outer(seq_len(n), seq_len(n), function(i, j) 7 * i + 3 * j + 1)))
}
emit("clue_cons", "clue", list(cases))
