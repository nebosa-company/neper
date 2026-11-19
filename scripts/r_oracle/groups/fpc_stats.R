# fpc: cluster.stats in full (noise cluster, every vector and matrix output, silhouette/G2/G3/wgap/sepindex switches, sepprob, sepwithnoise, aggregateonly,
# compareonly, non-euclidean distances, dbscan labels fed as a noise cluster).
#   "cs": (n, cn, cn2, flags, noise, sepwithnoise, sepprob, nsel, sel[nsel], cl[n], cl2[n] when cn2 > 0, as.dist order distances)
#         flags: 1 silhouette 2 G2 4 G3 8 wgap 16 sepindex; the answer is sum((position + 1) * out[sel]) with NA as -7777; out layout is in fpc.e (cs_len)
#   "cmp": (n, cn, cn2, cl[n], cl2[n]) answer corrected.rand + 2 vi
#   "csdb": (n, p, eps, minpts, nsel, sel[nsel], x row-major): fpc::dbscan, 0 relabelled to the last cluster, cluster.stats(noisecluster = TRUE, all switches)
suppressMessages(library(fpc))
cases <- list()
set.seed(20269911)
sc <- c("average.between", "average.within", "max.diameter", "min.separation", "within.cluster.ss", "avg.silwidth", "g2", "g3", "pearsongamma", "dunn", "dunn2",
        "entropy", "wb.ratio", "ch", "widestgap", "sindex", "corrected.rand", "vi", "n.between", "n.within", "min.cluster.size", "noisen", "ave.within.cluster.ss")
vc <- c("cluster.size", "diameter", "average.distance", "median.distance", "separation", "average.toother", "clus.avg.silwidths", "cwidegap")
mc <- c("separation.matrix", "ave.between.matrix")
slots <- function(s, cn) {
  idx <- integer(0); val <- numeric(0)
  for (i in seq_along(sc)) if (!is.null(s[[sc[i]]])) { idx <- c(idx, i - 1); val <- c(val, s[[sc[i]]]) }
  for (j in seq_along(vc)) { v <- s[[vc[j]]]; if (!is.null(v)) { idx <- c(idx, 24 + (j - 1) * cn + seq_along(v) - 1); val <- c(val, v) } }
  for (j in seq_along(mc)) { m <- s[[mc[j]]]; if (!is.null(m)) { idx <- c(idx, 24 + 8 * cn + (j - 1) * cn * cn + seq_len(cn * cn) - 1); val <- c(val, as.vector(m)) } }
  list(idx = idx, val = val)
}
chk <- function(v) sum((seq_along(v)) * ifelse(is.finite(v), v, -7777))
mk <- function(n, cn, single) {
  repeat {
    cl <- if (single) c(1, sample(2:cn, n - 1, TRUE)) else sample(cn, n, TRUE)
    if (length(unique(cl)) == cn) return(sample(cl))
  }
}
addcs <- function(n, cn, cn2, flags, noise, sepwn, sepprob, sel, cl, cl2, dv, want) {
  cases[[length(cases) + 1]] <<- case("cs", c(n, cn, cn2, flags, as.numeric(noise), as.numeric(sepwn), sepprob, length(sel), sel, cl, if (cn2 > 0) cl2, dv), want, rel = 1e-8, abs = 1e-9)
}
for (rep in 1:30) {
  n <- sample(14:34, 1); noise <- rep %% 2 == 0; cn <- sample(if (noise) 3:5 else 2:5, 1)
  cl <- mk(n, cn, rep %% 3 == 0)
  p <- sample(2:3, 1); X <- matrix(round(rnorm(n * p) * 2 + cl, 3), n, p)
  d <- switch(rep %% 3 + 1, dist(X), dist(X, "manhattan"), as.dist(`diag<-`({m <- matrix(round(runif(n * n), 4) + 0.01, n); (m + t(m)) / 2}, 0)))
  flags <- sample(0:31, 1); if (rep <= 10) flags <- 31
  sepwn <- !(rep %% 4 == 0); sepprob <- c(0.1, 0.2, 0.3)[rep %% 3 + 1]
  cn2 <- if (rep %% 5 == 0) 0 else sample(2:4, 1); cl2 <- if (cn2 > 0) mk(n, cn2, FALSE) else NULL
  s <- suppressWarnings(cluster.stats(d, cl, alt.clustering = cl2, noisecluster = noise, silhouette = bitwAnd(flags, 1) > 0, G2 = bitwAnd(flags, 2) > 0, G3 = bitwAnd(flags, 4) > 0,
                     wgap = bitwAnd(flags, 8) > 0, sepindex = bitwAnd(flags, 16) > 0, sepprob = sepprob, sepwithnoise = sepwn))
  sl <- slots(s, cn); dv <- as.vector(d)
  scal <- sl$idx < 24; vec <- sl$idx >= 24 & sl$idx < 24 + 8 * cn; mat <- sl$idx >= 24 + 8 * cn
  for (g in list(scal, vec, mat)) if (any(g)) addcs(n, cn, cn2, flags, noise, sepwn, sepprob, sl$idx[g], cl, cl2, dv, chk(sl$val[g]))
  if (rep %% 3 == 1) {
    s2 <- suppressWarnings(cluster.stats(d, cl, alt.clustering = cl2, noisecluster = noise, aggregateonly = TRUE, G2 = TRUE, G3 = TRUE, sepprob = sepprob, sepwithnoise = sepwn))
    sl <- slots(s2, cn); addcs(n, cn, cn2, 31, noise, sepwn, sepprob, sl$idx, cl, cl2, dv, chk(sl$val))
  }
}
# compareonly
for (rep in 1:8) {
  n <- sample(10:60, 1); cn <- sample(2:5, 1); cn2 <- sample(2:6, 1); cl <- mk(n, cn, rep %% 2 == 0); cl2 <- mk(n, cn2, FALSE)
  s <- cluster.stats(clustering = cl, alt.clustering = cl2, compareonly = TRUE)
  cases[[length(cases) + 1]] <- case("cmp", c(n, cn, cn2, cl, cl2), s$corrected.rand + 2 * s$vi, rel = 1e-9, abs = 1e-11)
}
# dbscan labels as the noise cluster
done <- 0; rep <- 0
while (done < 8 && rep < 200) {
  rep <- rep + 1
  k <- sample(2:4, 1); m <- sample(15:25, k, replace = TRUE); ctr <- matrix(runif(k * 2, 0, 8), k, 2)
  x <- do.call(rbind, lapply(seq_len(k), function(g) matrix(rnorm(m[g] * 2, 0, 0.6), m[g], 2) + rep(ctr[g, ], each = m[g])))
  x <- round(rbind(x, matrix(runif(12, -1, 9), 6, 2)), 4); n <- nrow(x)
  eps <- c(0.6, 0.8, 1.0)[rep %% 3 + 1]; mp <- c(3, 4, 5)[rep %% 3 + 1]
  r <- dbscan(x, eps = eps, MinPts = mp); cl <- r$cluster
  if (!any(cl == 0) || max(cl) < 3) next
  cl[cl == 0] <- max(cl) + 1; cn <- max(cl)
  s <- suppressWarnings(cluster.stats(dist(x), cl, noisecluster = TRUE, G2 = TRUE, G3 = TRUE))
  sl <- slots(s, cn); done <- done + 1
  cases[[length(cases) + 1]] <- case("csdb", c(n, 2, eps, mp, length(sl$idx), sl$idx, as.vector(t(x))), chk(sl$val), rel = 1e-8, abs = 1e-9)
}
emit("fpc_stats", "fpc", list(cases))
