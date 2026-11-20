# ade4 dudi.pca and dudi.coa. Args: (kind, n, p, nf, what, idx, table row-major...): kind 0 dudi.pca (scaled), 1 dudi.pca (centred only), 2 dudi.coa, 3 dudi.acm (n by p is then rows by factors, 0-based level codes), 4 the between-class analysis bca and 5 the within-class analysis wca of the scaled dudi.pca of the table with the class codes appended after the table (what 6 is the ratio);
# what 0 is eig[idx], 1 c1, 2 li, 3 co, 4 l1 (row-major, nf columns), 5 the rank (idx unused).
suppressMessages(library(ade4))
cases <- list()
rq <- function(x, d) round(x * 64) / 64  # binary-exact inputs keep the oracle file small
set.seed(20261501)
one <- function(kind, x, nf) {
  n <- nrow(x); p <- ncol(x)
  d <- as.data.frame(x)
  if (kind == 3) d <- as.data.frame(lapply(d, factor))
  r <- switch(kind + 1, dudi.pca(d, scannf = FALSE, nf = nf), dudi.pca(d, scale = FALSE, scannf = FALSE, nf = nf), dudi.coa(d, scannf = FALSE, nf = nf), dudi.acm(d, scannf = FALSE, nf = nf))
  flat <- as.vector(t(x))
  hdr <- function(what, idx) c(kind, n, p, nf, what, idx, flat)
  for (k in seq_along(r$eig)) cases[[length(cases) + 1]] <<- case("d", hdr(0, k - 1), r$eig[k], rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <<- case("d", hdr(5, 0), r$rank, rel = 0, abs = 0)
  mats <- list(as.matrix(r$c1), as.matrix(r$li), as.matrix(r$co), as.matrix(r$l1))
  for (w in 1:4) { m <- mats[[w]]; v <- as.vector(t(m)); for (k in seq_along(v)) cases[[length(cases) + 1]] <<- case("d", hdr(w, k - 1), v[k], rel = 1e-9, abs = 1e-12) }
}
x1 <- rq(matrix(rnorm(9 * 4), 9, 4) + outer(1:9, c(1, -1, 0.5, 2)) * 0.3, 4)
one(0, x1, 3); one(1, x1, 2)
x2 <- rq(matrix(rnorm(4 * 7), 4, 7), 4)            # fewer rows than columns: the transposed branch
one(0, x2, 2)
x3 <- matrix(rpois(6 * 5, 8) + 1, 6, 5)
one(2, x3, 3)
x4 <- matrix(rpois(4 * 6, 5) + 1, 4, 6)
one(2, x4, 2)
x5 <- cbind(sample(0:2, 20, TRUE), sample(0:3, 20, TRUE), sample(0:1, 20, TRUE)); x5[1:3, 1] <- 0:2; x5[1:4, 2] <- 0:3; x5[1:2, 3] <- 0:1
one(3, x5, 3)
{ f5 <- as.data.frame(lapply(as.data.frame(x5), factor)); ra <- dudi.acm(f5, scannf = FALSE, nf = 3); v <- as.vector(t(as.matrix(ra$cr)))
  for (k in seq_along(v)) cases[[length(cases) + 1]] <- case("d", c(3, nrow(x5), ncol(x5), 3, 6, k - 1, as.vector(t(x5))), v[k], rel = 1e-9, abs = 1e-12) }
one2 <- function(kind, x, fac, nf) {
  n <- nrow(x); p <- ncol(x); f <- factor(fac)
  base <- dudi.pca(as.data.frame(x), scannf = FALSE, nf = 3)
  r <- if (kind == 4) bca(base, f, scannf = FALSE, nf = nf) else wca(base, f, scannf = FALSE, nf = nf)
  flat <- c(as.vector(t(x)), fac)
  hdr <- function(what, idx) c(kind, n, p, nf, what, idx, flat)
  for (k in seq_along(r$eig)) cases[[length(cases) + 1]] <<- case("d", hdr(0, k - 1), r$eig[k], rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <<- case("d", hdr(5, 0), r$rank, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <<- case("d", hdr(6, 0), r$ratio, rel = 1e-9, abs = 1e-12)
  mats <- list(as.matrix(r$c1), as.matrix(r$li), as.matrix(r$co), as.matrix(r$l1))
  for (w in 1:4) { m <- mats[[w]]; v <- as.vector(t(m)); for (k in seq_along(v)) cases[[length(cases) + 1]] <<- case("d", hdr(w, k - 1), v[k], rel = 1e-9, abs = 1e-12) }
}
fc <- c(0, 1, 2, 0, 1, 2, 0, 1, 2)
one2(4, x1, fc, 2); one2(5, x1, fc, 2)
fc6 <- c(0, 1, 0, 1, 0, 1, 2, 2, 2, 0, 1)
x6 <- rq(matrix(rnorm(11 * 6), 11, 6), 4)
one2(4, x6, fc6, 2); one2(5, x6, fc6, 3)
# coinertia of two scaled PCAs: args (6, n, px, nf, what, idx, X table, Y table ncol py = args via nf slot is not free, so py rides first after the table): the layout is
# (6, n, px, nf, what, idx, py, X row-major, Y row-major); what 0 eig, 1 c1, 2 l1, 3 lX, 4 lY, 5 rank, 6 RV, 7 li, 8 co
oneci <- function(x, y, nf) {
  n <- nrow(x); px <- ncol(x); py <- ncol(y)
  dx <- dudi.pca(as.data.frame(x), scannf = FALSE, nf = 3); dy <- dudi.pca(as.data.frame(y), scannf = FALSE, nf = 3)
  r <- coinertia(dx, dy, scannf = FALSE, nf = nf)
  flat <- c(py, as.vector(t(x)), as.vector(t(y)))
  hdr <- function(what, idx) c(6, n, px, nf, what, idx, flat)
  for (k in seq_along(r$eig)) cases[[length(cases) + 1]] <<- case("d", hdr(0, k - 1), r$eig[k], rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <<- case("d", hdr(5, 0), r$rank, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <<- case("d", hdr(6, 0), r$RV, rel = 1e-9, abs = 1e-12)
  mats <- list(as.matrix(r$c1), as.matrix(r$l1), as.matrix(r$lX), as.matrix(r$lY), NULL, NULL, as.matrix(r$li), as.matrix(r$co))
  for (w in c(1:4, 7:8)) { m <- mats[[w]]; v <- as.vector(t(m)); for (k in seq_along(v)) cases[[length(cases) + 1]] <<- case("d", hdr(w, k - 1), v[k], rel = 1e-9, abs = 1e-12) }
}
xa <- rq(matrix(rnorm(12 * 4), 12, 4), 4); ya <- rq(matrix(rnorm(12 * 3), 12, 3) + 0.5 * xa[, 1:3], 4)
oneci(xa, ya, 2)
xb <- rq(matrix(rnorm(10 * 3), 10, 3), 4); yb <- rq(matrix(rnorm(10 * 5), 10, 5) + xb[, c(1, 2, 3, 1, 2)], 4)
oneci(xb, yb, 3)
# procuste: (7, n, px, nf, what, idx, py, scale, X row-major, Y row-major); what 0 d[idx], 1 loadX, 2 loadY, 3 scorX, 4 scorY, 5 rank
onepr <- function(x, y, nf, sc) {
  n <- nrow(x); px <- ncol(x); py <- ncol(y)
  r <- procuste(as.data.frame(x), as.data.frame(y), scale = sc, nf = nf)
  flat <- c(py, as.numeric(sc), as.vector(t(x)), as.vector(t(y)))
  hdr <- function(what, idx) c(7, n, px, nf, what, idx, flat)
  for (k in seq_along(r$d)) cases[[length(cases) + 1]] <<- case("d", hdr(0, k - 1), r$d[k], rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <<- case("d", hdr(5, 0), r$rank, rel = 0, abs = 0)
  mats <- list(as.matrix(r$loadX), as.matrix(r$loadY), as.matrix(r$scorX), as.matrix(r$scorY))
  for (w in 1:4) { m <- mats[[w]]; v <- as.vector(t(m)); for (k in seq_along(v)) cases[[length(cases) + 1]] <<- case("d", hdr(w, k - 1), v[k], rel = 1e-9, abs = 1e-12) }
  if (!is.null(r$rotX)) for (w in 6:7) { m <- as.matrix(if (w == 6) r$rotX else r$rotY); v <- as.vector(t(m)); for (k in seq_along(v)) cases[[length(cases) + 1]] <<- case("d", hdr(w, k - 1), v[k], rel = 1e-9, abs = 1e-12) }
}
xp <- rq(matrix(rnorm(15 * 3), 15, 3), 4); yp <- rq(matrix(rnorm(15 * 3), 15, 3) + xp, 4)
xp <- xp[1:9, ]; yp <- yp[1:9, ]  # drawn at 15 rows so the later random streams are unchanged, checked on 9
onepr(xp, yp, 4, TRUE); onepr(xp, yp, 2, FALSE)
xq <- rq(matrix(rnorm(12 * 4), 12, 4), 4); yq <- rq(matrix(rnorm(12 * 2), 12, 2) + xq[, 1:2], 4)
onepr(xq, yq, 4, TRUE)
# dudi.fca: (8, n, p, nf, what, idx, nb, rw (n), table row-major); what 0 eig, 1 c1, 2 li, 3 co, 4 l1, 5 rank
lr <- function(p, S) { f <- p * S; b <- floor(f); r <- S - sum(b); if (r > 0) { o <- order(f - b, decreasing = TRUE)[seq_len(r)]; b[o] <- b[o] + 1 }; b / S }  # largest remainder: binary-exact shares summing to 1
onefca <- function(blocks, n0, nf, n) {
  p <- sum(blocks)
  tab <- matrix(0, n, p); k <- 0
  for (b in blocks) { m <- matrix(runif(n0 * b), n0, b); m <- m / rowSums(m); for (i in seq_len(n)) tab[i, k + seq_len(b)] <- lr(m[i, ], 16); k <- k + b }
  rw <- runif(n0)[seq_len(n)]; rw <- lr(rw / sum(rw), 256)
  df <- as.data.frame(tab)
  names(blocks) <- paste0("v", seq_along(blocks))
  attr(df, "col.blocks") <- blocks; attr(df, "row.w") <- rw; attr(df, "col.num") <- factor(rep(seq_along(blocks), blocks))
  r <- dudi.fca(df, scannf = FALSE, nf = nf)
  flat <- c(length(blocks), rw, as.vector(t(tab)))
  hdr <- function(what, idx) c(8, n, p, nf, what, idx, flat)
  for (k in seq_along(r$eig)) cases[[length(cases) + 1]] <<- case("d", hdr(0, k - 1), r$eig[k], rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <<- case("d", hdr(5, 0), r$rank, rel = 0, abs = 0)
  mats <- list(as.matrix(r$c1), as.matrix(r$li), as.matrix(r$co), as.matrix(r$l1))
  for (w in 1:4) { m <- mats[[w]]; v <- as.vector(t(m)); for (k in seq_along(v)) cases[[length(cases) + 1]] <<- case("d", hdr(w, k - 1), v[k], rel = 1e-9, abs = 1e-12) }
}
onefca(c(3, 2, 3), 14, 3, 10)
onefca(c(2, 4), 10, 2, 8)
# rlq: (9, n, pr, nf, what, idx, nl, pq, R row-major, L row-major (equal row totals), Q row-major); what 0 eig, 1 c1, 2 l1, 3 lR, 4 lQ, 5 rank
onerlq <- function(n, pr, nl, pq, nf) {
  R <- matrix(rnorm(n * pr), n, pr)
  L <- t(sapply(seq_len(n), function(i) as.vector(rmultinom(1, 30, runif(nl) + 0.2))))
  L <- L[, order(colSums(L), decreasing = TRUE)]
  Q <- matrix(rnorm(nl * pq), nl, pq)
  dR <- dudi.pca(as.data.frame(R), scannf = FALSE)
  dL <- dudi.coa(as.data.frame(L), scannf = FALSE)
  dQ <- dudi.pca(as.data.frame(Q), row.w = dL$cw, scannf = FALSE)
  r <- rlq(dR, dL, dQ, scannf = FALSE, nf = nf)
  flat <- c(nl, pq, as.vector(t(R)), as.vector(t(L)), as.vector(t(Q)))
  hdr <- function(what, idx) c(9, n, pr, nf, what, idx, flat)
  for (k in seq_along(r$eig)) cases[[length(cases) + 1]] <<- case("d", hdr(0, k - 1), r$eig[k], rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <<- case("d", hdr(5, 0), r$rank, rel = 0, abs = 0)
  mats <- list(as.matrix(r$c1), as.matrix(r$l1), as.matrix(r$lR), as.matrix(r$lQ))
  for (w in 1:4) { m <- mats[[w]]; v <- as.vector(t(m)); for (k in seq_along(v)) cases[[length(cases) + 1]] <<- case("d", hdr(w, k - 1), v[k], rel = 1e-9, abs = 1e-12) }
}
onerlq(12, 3, 5, 2, 2)
onerlq(15, 4, 6, 3, 2)
# dudi.mix: (10, n, nv, nf, what, idx, kinds (nv: 0 quantitative, 1 factor, 2 ordered factor, 3 quantitative under add.square), table row-major with 0-based codes); what 0 eig, 1 c1, 2 li, 3 co, 4 l1, 5 rank, 6 cr
onemix <- function(n, kinds, nlev, nf) {
  flat <- matrix(0, n, length(kinds))
  df <- data.frame(row.names = seq_len(n))
  for (j in seq_along(kinds)) {
    if (kinds[j] %in% c(0, 3)) { v <- rnorm(n); flat[, j] <- v; df[[paste0("q", j)]] <- v }
    else { f <- sample(0:(nlev[j] - 1), n, TRUE); f[seq_len(nlev[j])] <- 0:(nlev[j] - 1); flat[, j] <- f; df[[paste0("f", j)]] <- factor(f, ordered = kinds[j] == 2) }
  }
  r <- dudi.mix(df, add.square = any(kinds == 3), scannf = FALSE, nf = nf)
  hdr <- function(what, idx) c(10, n, length(kinds), nf, what, idx, kinds, as.vector(t(flat)))
  for (k in seq_along(r$eig)) cases[[length(cases) + 1]] <<- case("d", hdr(0, k - 1), r$eig[k], rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <<- case("d", hdr(5, 0), r$rank, rel = 0, abs = 0)
  mats <- list(as.matrix(r$c1), as.matrix(r$li), as.matrix(r$co), as.matrix(r$l1), as.matrix(r$cr))
  for (w in 1:5) { m <- mats[[w]]; v <- as.vector(t(m)); for (k in seq_along(v)) cases[[length(cases) + 1]] <<- case("d", hdr(if (w == 5) 6 else w, k - 1), v[k], rel = 1e-9, abs = 1e-12) }
}
onemix(20, c(0, 1, 0, 1), c(0, 3, 0, 4), 3)
onemix(15, c(1, 0, 1), c(2, 0, 3), 2)
onemix(24, c(2, 0, 1, 2), c(4, 0, 3, 2), 3)
onemix(18, c(2, 2, 0), c(3, 5, 0), 3)
onemix(22, c(3, 3, 3), c(0, 0, 0), 3)
# prep.fuzzy.var and dudi.fpca: (11, n, p, nf, what, idx, nb, blocks (nb), rw (n), raw table row-major); what 0 eig, 1 c1, 2 li, 3 co, 4 l1, 5 rank, 6 prepared table, 7 row.w, 8 col.freq
onefpca <- function(blocks, n, nf, zero_rows = integer(0), zero_w = integer(0)) {
  p <- sum(blocks)
  tab <- matrix(rpois(n * p, 2), n, p)
  k <- 0
  for (b in blocks) { tab[zero_rows, k + seq_len(b)] <- 0; k <- k + b }
  rw <- rq(runif(n) + 0.1); rw[rw == 0] <- 1 / 64; rw[zero_w] <- 0
  df <- as.data.frame(tab)
  pf <- prep.fuzzy.var(df, blocks, row.w = rw)
  r <- dudi.fpca(pf, scannf = FALSE, nf = nf)
  hdr <- function(what, idx) c(11, n, p, nf, what, idx, length(blocks), blocks, rw, as.vector(t(tab)))
  for (k in seq_along(r$eig)) cases[[length(cases) + 1]] <<- case("d", hdr(0, k - 1), r$eig[k], rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <<- case("d", hdr(5, 0), r$rank, rel = 0, abs = 0)
  mats <- list(as.matrix(r$c1), as.matrix(r$li), as.matrix(r$co), as.matrix(r$l1))
  for (w in 1:4) { m <- mats[[w]]; v <- as.vector(t(m)); for (k in seq_along(v)) cases[[length(cases) + 1]] <<- case("d", hdr(w, k - 1), v[k], rel = 1e-9, abs = 1e-12) }
  v <- as.vector(t(as.matrix(pf))); for (k in seq_along(v)) cases[[length(cases) + 1]] <<- case("d", hdr(6, k - 1), v[k], rel = 1e-9, abs = 1e-12)
  rwp <- attr(pf, "row.w"); for (k in seq_along(rwp)) cases[[length(cases) + 1]] <<- case("d", hdr(7, k - 1), rwp[k], rel = 1e-9, abs = 1e-12)
  cf <- attr(pf, "col.freq"); for (k in seq_along(cf)) cases[[length(cases) + 1]] <<- case("d", hdr(8, k - 1), cf[k], rel = 1e-9, abs = 1e-12)
}
onefpca(c(3, 2, 3), 12, 3)
onefpca(c(2, 4), 10, 2, zero_rows = c(3, 7))
onefpca(c(3, 3, 2), 10, 3, zero_rows = 5, zero_w = 9)
# both tables wider than tall: ade4's nonsymmetric coinertia branch (dgeev); drawn last so the earlier cases keep their random streams
xw <- rq(matrix(rnorm(5 * 8), 5, 8), 4); yw <- rq(matrix(rnorm(5 * 7), 5, 7) + xw[, c(1:5, 1:2)] * 0.7, 4)
oneci(xw, yw, 3)
xw2 <- rq(matrix(rnorm(6 * 9), 6, 9), 4); yw2 <- rq(matrix(rnorm(6 * 8), 6, 8) + 0.3 * xw2[, 1:8], 4)
oneci(xw2, yw2, 2)
# dudi.pco of the euclidean distances between the rows of a point table: (12, n, k, nf, what, idx, rw (n), points row-major); what 0 eig, 1 c1, 2 li, 3 co, 4 l1, 5 rank, 6 tab
onepco <- function(n, k, nf, weighted) {
  x <- rq(matrix(rnorm(n * k), n, k), 4)
  rw <- if (weighted) { w <- rq(runif(n) + 0.1); w[w == 0] <- 1 / 64; w } else rep(1, n)
  r <- dudi.pco(dist(x), row.w = rw, scannf = FALSE, nf = nf)
  hdr <- function(what, idx) c(12, n, k, nf, what, idx, rw, as.vector(t(x)))
  for (q in seq_along(r$eig)) cases[[length(cases) + 1]] <<- case("d", hdr(0, q - 1), r$eig[q], rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <<- case("d", hdr(5, 0), r$rank, rel = 0, abs = 0)
  mats <- list(as.matrix(r$c1), as.matrix(r$li), as.matrix(r$co), as.matrix(r$l1), NULL, as.matrix(r$tab))
  for (w in c(1:4, 6)) { m <- mats[[w]]; v <- as.vector(t(m)); for (q in seq_along(v)) cases[[length(cases) + 1]] <<- case("d", hdr(w, q - 1), v[q], rel = 1e-9, abs = 1e-12) }
}
onepco(9, 3, 2, FALSE)
onepco(11, 4, 3, TRUE)
# dudi.hillsmith: (13, n, nv, nf, what, idx, kinds (0 quantitative, 1 factor), rw (n), table row-major with 0-based codes); what 0 eig, 1 c1, 2 li, 3 co, 4 l1, 5 rank
onehs <- function(n, kinds, nlev, nf, weighted) {
  flat <- matrix(0, n, length(kinds)); df <- data.frame(row.names = seq_len(n))
  for (j in seq_along(kinds)) {
    if (kinds[j] == 0) { v <- rq(rnorm(n), 4); flat[, j] <- v; df[[paste0("q", j)]] <- v }
    else { f <- sample(0:(nlev[j] - 1), n, TRUE); f[seq_len(nlev[j])] <- 0:(nlev[j] - 1); flat[, j] <- f; df[[paste0("f", j)]] <- factor(f) }
  }
  rw <- if (weighted) { w <- rq(runif(n) + 0.1); w[w == 0] <- 1 / 64; w } else rep(1, n)
  r <- dudi.hillsmith(df, row.w = rw, scannf = FALSE, nf = nf)
  hdr <- function(what, idx) c(13, n, length(kinds), nf, what, idx, kinds, rw, as.vector(t(flat)))
  for (q in seq_along(r$eig)) cases[[length(cases) + 1]] <<- case("d", hdr(0, q - 1), r$eig[q], rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <<- case("d", hdr(5, 0), r$rank, rel = 0, abs = 0)
  mats <- list(as.matrix(r$c1), as.matrix(r$li), as.matrix(r$co), as.matrix(r$l1))
  for (w in 1:4) { m <- mats[[w]]; v <- as.vector(t(m)); for (q in seq_along(v)) cases[[length(cases) + 1]] <<- case("d", hdr(w, q - 1), v[q], rel = 1e-9, abs = 1e-12) }
}
onehs(12, c(0, 1, 0, 1), c(0, 3, 0, 4), 2, FALSE)
onehs(14, c(1, 0, 1), c(3, 0, 2), 2, TRUE)
onehs(15, c(0, 0, 1, 0), c(0, 0, 4, 0), 2, TRUE)
# prep.binary: (14, n, p, 0, 0, idx, nb, blocks, table row-major), NA reported as -1; then dudi.fca of a binary table (kind 8)
onebin <- function(blocks, n) {
  p <- sum(blocks)
  raw <- matrix(rpois(n * p, 0.7), n, p)
  r <- prep.binary(as.data.frame(raw), blocks)
  v <- as.vector(t(as.matrix(r))); v[is.na(v)] <- -1
  for (q in seq_along(v)) cases[[length(cases) + 1]] <<- case("d", c(14, n, p, 0, 0, q - 1, length(blocks), blocks, as.vector(t(raw))), v[q], rel = 0, abs = 0)
  raw2 <- raw
  k <- 0; for (b in blocks) { z <- which(rowSums(raw2[, k + seq_len(b), drop = FALSE]) == 0); raw2[z, k + 1] <- 1; k <- k + b }
  r2 <- prep.binary(as.data.frame(raw2), blocks)
  rw <- runif(n) + 0.1; rw <- lr(rw / sum(rw), 256)
  attr(r2, "row.w") <- rw
  f <- dudi.fca(r2, scannf = FALSE, nf = 2)
  hdr <- function(what, idx) c(8, n, p, 2, what, idx, length(blocks), rw, as.vector(t(as.matrix(r2))))
  for (q in seq_along(f$eig)) cases[[length(cases) + 1]] <<- case("d", hdr(0, q - 1), f$eig[q], rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <<- case("d", hdr(5, 0), f$rank, rel = 0, abs = 0)
  mats <- list(as.matrix(f$c1), as.matrix(f$li), as.matrix(f$co), as.matrix(f$l1))
  for (w in 1:4) { m <- mats[[w]]; v <- as.vector(t(m)); for (q in seq_along(v)) cases[[length(cases) + 1]] <<- case("d", hdr(w, q - 1), v[q], rel = 1e-9, abs = 1e-12) }
}
onebin(c(3, 2, 3), 9)
# prep.circular: (15, n, p, 0, what, idx, rmin (p), rmax (p), table row-major); what 0 table, 1 max
onecirc <- function(n, p) {
  x <- matrix(sample(0:11, n * p, TRUE), n, p)
  rmin <- apply(x, 2, min) - sample(0:2, p, TRUE); rmax <- apply(x, 2, max) + sample(0:2, p, TRUE)
  r <- prep.circular(as.data.frame(x), rmin, rmax)
  hdr <- function(what, idx) c(15, n, p, 0, what, idx, rmin, rmax, as.vector(t(x)))
  v <- as.vector(t(as.matrix(r))); for (q in seq_along(v)) cases[[length(cases) + 1]] <<- case("d", hdr(0, q - 1), v[q], rel = 0, abs = 0)
  v <- attr(r, "max"); for (q in seq_along(v)) cases[[length(cases) + 1]] <<- case("d", hdr(1, q - 1), v[q], rel = 0, abs = 0)
}
onecirc(6, 3)
emit("ade4_dudi", "ade4", list(cases))
