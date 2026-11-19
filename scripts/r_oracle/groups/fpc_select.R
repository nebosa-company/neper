# fpc::nselectboot and fpc::prediction.strength under set.seed with hclustCBI / disthclustCBI and the classifications averagedist, centroid, fn and knn (nnk = 1).
#   "sel": (fn, what, n, p, distances, B, hmethod, hscaling, kmin, kmax, classification, cutoff, seed, data n by p row-major or the n by n dissimilarities)
#   fn 1 nselectboot: what 0 sum (rep * kmax + k) * stab[rep, k], 1 sum k * stabk[k], 2 kopt;
#   fn 2 prediction.strength (B is M): what 0 sum ((k - kmin) * M + l) * corrpred[[k]][l] (l from 1), 1 sum k * mean.pred[k] for k in kmin..kmax, 2 optimalk
#   classification 1 averagedist, 2 centroid, 3 fn, 4 knn
suppressMessages(library(fpc))
cases <- list()
set.seed(20269951)
hm <- c("ward.D", "single", "complete", "average")
cn <- c("averagedist", "centroid", "fn", "knn")
blobs <- function(n, p, k) {
  m <- rep(n %/% k, k); m[1] <- m[1] + n - sum(m); ctr <- matrix(runif(k * p, 0, 7), k, p)
  round(do.call(rbind, lapply(seq_len(k), function(g) matrix(rnorm(m[g] * p, 0, 0.8), m[g], p) + rep(ctr[g, ], each = m[g]))), 4)
}
one <- function(x, dist, B, hmeth, sc, kmin, kmax, cl, seed, cutoff = 0.8, nnk = 1) {
  n <- nrow(x); p <- ncol(x)
  dat <- if (dist) as.vector(t(as.matrix(dist(x)))) else as.vector(t(x))
  hdr <- function(f, w) c(f, w, n, p, as.numeric(dist), B, hmeth, as.numeric(sc), kmin, kmax, cl + 10 * (nnk - 1), cutoff, seed, dat)
  cm <- if (dist) disthclustCBI else if (hmeth == 0) kmeansCBI else hclustCBI
  ex <- if (dist) list(method = hm[hmeth]) else if (hmeth == 0) list(scaling = sc) else list(method = hm[hmeth], scaling = sc)
  set.seed(seed)
  r <- do.call(nselectboot, c(list(data = if (dist) dist(x) else x, B = B, clustermethod = cm, classification = cn[cl], krange = kmin:kmax, distances = dist, nnk = nnk), ex))
  add <- function(f, w, v) cases[[length(cases) + 1]] <<- case("sel", hdr(f, w), v, rel = 1e-9, abs = 1e-9)
  st <- r$stab
  add(1, 0, sum(((row(st) - 1) * kmax + col(st)) * st))
  add(1, 1, sum((kmin:kmax) * r$stabk[kmin:kmax]))
  add(1, 2, r$kopt)
  set.seed(seed)
  rl <- do.call(nselectboot, c(list(data = if (dist) dist(x) else x, B = B, clustermethod = cm, classification = cn[cl], krange = kmin:kmax, distances = dist, nnk = nnk, largeisgood = TRUE), ex))
  add(1, 3, sum((kmin:kmax) * rl$stabk[kmin:kmax]))
  set.seed(seed)
  pr <- try(do.call(prediction.strength, c(list(xdata = if (dist) dist(x) else x, Gmin = kmin, Gmax = kmax, M = B, clustermethod = cm, classification = cn[cl], cutoff = cutoff, nnk = nnk,
                                           distances = dist), ex)), silent = TRUE)
  # prediction.strength hands classifdist a dist object, whose nrow is NULL: R stops for knn with nnk > 1 on dissimilarities, so there is no case
  if (inherits(pr, "try-error")) return(invisible(NULL))
  add(2, 0, sum(unlist(lapply(kmin:kmax, function(k) ((k - kmin) * B + seq_len(B)) * pr$predcorr[[k]]))))
  add(2, 1, sum((kmin:kmax) * pr$mean.pred[kmin:kmax]))
  add(2, 2, pr$optimalk)
}
for (rep in 1:8) {
  k <- sample(2:4, 1); x <- blobs(sample(28:44, 1), c(2, 3)[rep %% 2 + 1], k)
  one(x, FALSE, 10, c(3, 4, 1, 2)[rep %% 4 + 1], rep %% 3 != 0, 2, 5, c(1, 2, 3, 4)[rep %% 4 + 1], 300 + rep, cutoff = 0.5)
}
for (rep in 1:3) {
  x <- blobs(sample(28:40, 1), 2, 3)
  one(x, TRUE, 8, c(3, 4, 2)[rep], FALSE, 2, 5, c(1, 3, 4)[rep], 400 + rep, cutoff = 0.5)
}
# kmeansCBI (hmeth 0), prediction.strength's default clustermethod
for (rep in 1:4) {
  k <- sample(2:3, 1); x <- blobs(sample(30:44, 1), 2, k)
  one(x, FALSE, 8, 0, rep %% 2 == 0, 2, 4, c(4, 2, 4, 3)[rep], 500 + rep, cutoff = 0.5)
}
# knn with nnk > 1 (class::knn on the data, the k-nearest vote of classifdist on dissimilarities), kmeansCBI and hclustCBI, largeisgood in every nselectboot
for (rep in 1:5) {
  k <- sample(2:3, 1); x <- blobs(sample(30:44, 1), 2, k)
  one(x, FALSE, 8, c(0, 3, 4, 0, 1)[rep], rep %% 2 == 0, 2, 4, 4, 600 + rep, cutoff = 0.5, nnk = c(2, 3, 4, 3, 5)[rep])
}
for (rep in 1:3) {
  x <- blobs(sample(28:40, 1), 2, 3)
  one(x, TRUE, 8, c(3, 4, 2)[rep], FALSE, 2, 4, 4, 700 + rep, cutoff = 0.5, nnk = c(2, 3, 4)[rep])
}
emit("fpc_select", "fpc", list(cases))
