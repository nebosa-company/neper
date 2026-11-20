# fpc::clusterboot under set.seed with hclustCBI, disthclustCBI and dbscanCBI and the bootstrap, subset, jitter, bojit and noise resampling.
#   "cb": (what, meth, n, p, distances, B, nmeth, methods[nmeth], multipleboot, bscompare, jittertuning, noise1, noise2, subtuning, cm, cp1..cp4, noisemethod,
#          seed, dissolution, recover, data n by p row-major or the n by n dissimilarities)
#   what 0: sum over cluster j and replication i of (j * B + i + 1) * result[j, i] for method code meth (1 boot 2 subset 3 jitter 4 bojit 5 noise);
#   what 1: sum over j of (j + 1) * (mean_j + 1000 * brd_j + 1e6 * recover_j);   cm 1 hclustCBI (cp: method, k, scaling, noisecut), 2 dbscanCBI (eps, MinPts), 3 disthclustCBI
suppressMessages(library(fpc))
cases <- list()
set.seed(20269941)
hm <- c("ward.D", "single", "complete", "average")
nmv <- c("boot", "subset", "jitter", "bojit", "noise")
run <- function(x, B, meths, cm, cp, multipleboot = FALSE, bscompare = TRUE, noisemethod = FALSE, distances = FALSE, subtuning = NULL, seed = 1, jt = 0.05, nz = c(0.05, 4), diss = 0.5, rec = 0.75) {
  n <- nrow(x); p <- ncol(x)
  if (cm %in% c(6, 8, 9, 10, 11, 12, 15)) distances <- TRUE
  if (is.null(subtuning)) subtuning <- floor(n / 2)
  common <- list(B = B, bootmethod = nmv[meths], multipleboot = multipleboot, bscompare = bscompare, subtuning = subtuning, noisemethod = noisemethod, count = FALSE,
                 showplots = FALSE, seed = seed, distances = distances, jittertuning = jt, noisetuning = nz, dissolution = diss, recover = rec)
  r <- if (cm == 1) do.call(clusterboot, c(list(data = x, clustermethod = hclustCBI, method = hm[cp[1]], k = cp[2], scaling = cp[3] == 1, noisecut = cp[4]), common))
       else if (cm == 3) do.call(clusterboot, c(list(data = dist(x), clustermethod = disthclustCBI, method = hm[cp[1]], k = cp[2], noisecut = cp[4]), common))
       else if (cm == 4) do.call(clusterboot, c(list(data = x, clustermethod = kmeansCBI, k = cp[2], scaling = cp[3] == 1, runs = cp[1], criterion = c("ch", "asw")[cp[4] + 1]), common))
       else if (cm == 5) do.call(clusterboot, c(list(data = x, clustermethod = pamkCBI, k = cp[2], scaling = cp[3] == 1), common))
       else if (cm == 6) do.call(clusterboot, c(list(data = dist(x), clustermethod = pamkCBI, k = cp[2]), common))
       else if (cm == 7) do.call(clusterboot, c(list(data = x, clustermethod = claraCBI, k = cp[2]), common))
       else if (cm == 8) do.call(clusterboot, c(list(data = dist(x), clustermethod = claraCBI, k = cp[2]), common))
       else if (cm == 13) do.call(clusterboot, c(list(data = x, clustermethod = mahalCBI, method = c("fuzzy", "ml", "classical")[cp[1] + 1], ca = cp[2], ca2 = if (cp[1] == 0) cp[3] else NA, clustercut = cp[4], countmode = 1e9), common))
       else if (cm == 14) do.call(clusterboot, c(list(data = x, clustermethod = hclusttreeCBI, method = hm[cp[1]], minlevel = cp[2], scaling = cp[3] == 1), common))
       else if (cm == 15) do.call(clusterboot, c(list(data = dist(x), clustermethod = disthclusttreeCBI, method = hm[cp[1]], minlevel = cp[2]), common))
       else if (cm >= 9 && cm <= 12) do.call(clusterboot, c(list(data = dist(x), clustermethod = list(stupidkcentroidsCBI, stupidknnCBI, stupidkfnCBI, stupidkavenCBI)[[cm - 8]], k = cp[2]), common))
       else do.call(clusterboot, c(list(data = x, clustermethod = dbscanCBI, eps = cp[1], MinPts = cp[2]), common))
  if (cm == 7) cm <- 5
  if (cm == 8) cm <- 6
  if (cm >= 9) cm <- cm - 2
  if (cm == 6) distances <- TRUE
  dat <- if (distances || cm == 3) as.vector(t(as.matrix(dist(x)))) else as.vector(t(x))
  nm <- c("boot", "subset", "jitter", "bojit", "noise")
  for (m in meths) {
    res <- r[[paste0(nm[m], "result")]]
    nc <- nrow(res)
    hdr <- function(w) c(w, m, n, p, as.numeric(distances || cm == 3), B, length(meths), meths, as.numeric(multipleboot), as.numeric(bscompare), jt, nz[1], nz[2], subtuning, cm, cp,
                         as.numeric(noisemethod), seed, diss, rec, dat)
    ck <- sum((seq_len(nc * B) - 1 + 1) * as.vector(t(res)))
    cases[[length(cases) + 1]] <<- case("cb", hdr(0), ck, rel = 1e-9, abs = 1e-9)
    mn <- r[[paste0(nm[m], "mean")]]; bd <- r[[paste0(nm[m], "brd")]]; rc <- r[[paste0(nm[m], "recover")]]
    cases[[length(cases) + 1]] <<- case("cb", hdr(1), sum(seq_len(nc) * (mn + 1000 * bd + 1e6 * rc)), rel = 1e-9, abs = 1e-9)
  }
}
blobs <- function(n, p, k) {
  m <- rep(n %/% k, k); m[1] <- m[1] + n - sum(m); ctr <- matrix(runif(k * p, 0, 6), k, p)
  round(do.call(rbind, lapply(seq_len(k), function(g) matrix(rnorm(m[g] * p, 0, 0.9), m[g], p) + rep(ctr[g, ], each = m[g]))), 4)
}
for (rep in 1:3) {
  x <- blobs(sample(30:44, 1), c(2, 3, 2)[rep], 3)
  run(x, 12, 1:5, 1, c(3, 3, 1, 0), seed = 100 + rep)
}
x <- blobs(36, 2, 3); run(x, 10, 1, 1, c(4, 4, 0, 0), multipleboot = TRUE, bscompare = TRUE, seed = 7)
run(x, 10, 1, 1, c(4, 3, 1, 0), multipleboot = TRUE, bscompare = FALSE, seed = 8)
run(x, 10, c(1, 2), 1, c(3, 4, 1, 2), seed = 9)
# a dissimilarity matrix: boot and subset, with noise clusters of size <= 3
x <- blobs(34, 2, 3)
run(x, 12, 1:2, 3, c(4, 3, 0, 0), distances = TRUE, seed = 11)
run(x, 12, 1:2, 3, c(3, 6, 0, 3), noisemethod = TRUE, distances = TRUE, seed = 12)
# dbscan with its noise cluster
for (rep in 1:3) {
  x <- rbind(blobs(30, 2, 2), matrix(runif(12, -1, 8), 6, 2)); x <- round(x, 4)
  run(x, 12, c(1, 2, 3, 5), 2, c(0.9, 4, 0, 0), noisemethod = TRUE, seed = 20 + rep)
}
# kmeansCBI, pamkCBI and claraCBI (pam)
for (rep in 1:4) {
  x <- blobs(sample(30:44, 1), c(2, 3)[rep %% 2 + 1], 3)
  run(x, 12, 1:5, 4, c(c(1, 3)[rep %% 2 + 1], 3, rep %% 2, 0), seed = 300 + rep)
}
x <- blobs(40, 2, 3)
run(x, 10, 1:3, 5, c(0, 3, 1, 0), seed = 311)
run(x, 10, 1:3, 7, c(0, 4, 0, 0), seed = 312)
run(x, 10, 1:2, 6, c(0, 3, 0, 0), seed = 313)
run(x, 10, 1:2, 8, c(0, 3, 0, 0), seed = 314)
# the random-start methods stupidkcentroidsCBI, stupidknnCBI, stupidkfnCBI and stupidkavenCBI (R cm 9 .. 12, Neper cm 7 .. 10)
for (rep in 1:4) {
  x <- blobs(sample(28:40, 1), 2, 3)
  run(x, 10, c(1, 2), 8 + rep, c(0, 3, 0, 0), seed = 320 + rep)
}
# the tuning knobs: jittertuning, noisetuning, dissolution and recover away from their defaults
x <- blobs(38, 2, 3)
run(x, 12, 1:5, 1, c(3, 3, 1, 0), seed = 401, jt = 0.15, nz = c(0.1, 2), diss = 0.3, rec = 0.9)
run(x, 12, 1:5, 1, c(4, 3, 0, 0), seed = 402, jt = 0.02, nz = c(0.02, 8), diss = 0.7, rec = 0.5)
run(x, 12, 1:5, 4, c(1, 3, 0, 0), seed = 403, jt = 0.1, nz = c(0.2, 3), diss = 0.4, rec = 0.6)
# hclusttreeCBI and disthclusttreeCBI: every merge of the tree is a cluster (R cm 14 and 15, Neper 12 and 13), with minlevel 2 and 1
x <- blobs(30, 2, 3)
run(x, 8, 1:5, 14, c(4, 2, 1, 0), seed = 501)
run(x, 8, 1:2, 14, c(3, 1, 0, 0), seed = 502)
run(x, 8, c(2, 1), 15, c(4, 2, 0, 0), seed = 503)
run(x, 8, 1:2, 15, c(2, 1, 0, 0), seed = 504)
# mahalCBI: fixmahal clusters (mode, ca, ca2, clustercut)
for (rep in 1:3) {
  x <- round(rbind(matrix(rnorm(70, 0, 0.8), 35, 2), matrix(rnorm(70, 6, 0.8), 35, 2)), 4)
  mode <- rep - 1
  ca <- if (mode == 0) qchisq(0.95, 2) else qchisq(0.99, 2); ca2 <- if (mode == 0) qchisq(0.995, 2) else 0
  run(x, 6, c(1, 3, 5), 13, c(mode, ca, ca2, c(0.5, 0.3, 0.5)[rep]), seed = 510 + rep)
}
emit("fpc_boot", "fpc", list(cases))
