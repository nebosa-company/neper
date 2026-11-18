# ade4 dudi.pca and dudi.coa. Args: (kind, n, p, nf, what, idx, table row-major...): kind 0 dudi.pca (scaled), 1 dudi.pca (centred only), 2 dudi.coa, 3 dudi.acm (n by p is then rows by factors, 0-based level codes), 4 the between-class analysis bca and 5 the within-class analysis wca of the scaled dudi.pca of the table with the class codes appended after the table (what 6 is the ratio);
# what 0 is eig[idx], 1 c1, 2 li, 3 co, 4 l1 (row-major, nf columns), 5 the rank (idx unused).
suppressMessages(library(ade4))
cases <- list()
set.seed(20261501)
one <- function(kind, x, nf) {
  n <- nrow(x); p <- ncol(x)
  d <- as.data.frame(x)
  if (kind == 3) d <- as.data.frame(lapply(d, factor))
  r <- switch(kind + 1, dudi.pca(d, scannf = FALSE, nf = nf), dudi.pca(d, scale = FALSE, scannf = FALSE, nf = nf), dudi.coa(d, scannf = FALSE, nf = nf), dudi.acm(d, scannf = FALSE, nf = nf))
  flat <- as.vector(t(x))
  hdr <- function(what, idx) c(kind, n, p, nf, what, idx, flat)
  for (k in seq_along(r$eig)) cases[[length(cases) + 1]] <<- case("d", hdr(0, k - 1), r$eig[k], rel = 1e-8, abs = 1e-12)
  cases[[length(cases) + 1]] <<- case("d", hdr(5, 0), r$rank, rel = 0, abs = 0)
  mats <- list(as.matrix(r$c1), as.matrix(r$li), as.matrix(r$co), as.matrix(r$l1))
  for (w in 1:4) { m <- mats[[w]]; v <- as.vector(t(m)); for (k in seq_along(v)) cases[[length(cases) + 1]] <<- case("d", hdr(w, k - 1), v[k], rel = 1e-7, abs = 1e-10) }
}
x1 <- matrix(rnorm(9 * 4), 9, 4) + outer(1:9, c(1, -1, 0.5, 2)) * 0.3
one(0, x1, 3); one(1, x1, 2)
x2 <- matrix(rnorm(4 * 7), 4, 7)            # fewer rows than columns: the transposed branch
one(0, x2, 2)
x3 <- matrix(rpois(6 * 5, 8) + 1, 6, 5)
one(2, x3, 3)
x4 <- matrix(rpois(4 * 6, 5) + 1, 4, 6)
one(2, x4, 2)
x5 <- cbind(sample(0:2, 20, TRUE), sample(0:3, 20, TRUE), sample(0:1, 20, TRUE)); x5[1:3, 1] <- 0:2; x5[1:4, 2] <- 0:3; x5[1:2, 3] <- 0:1
one(3, x5, 3)
one2 <- function(kind, x, fac, nf) {
  n <- nrow(x); p <- ncol(x); f <- factor(fac)
  base <- dudi.pca(as.data.frame(x), scannf = FALSE, nf = 3)
  r <- if (kind == 4) bca(base, f, scannf = FALSE, nf = nf) else wca(base, f, scannf = FALSE, nf = nf)
  flat <- c(as.vector(t(x)), fac)
  hdr <- function(what, idx) c(kind, n, p, nf, what, idx, flat)
  for (k in seq_along(r$eig)) cases[[length(cases) + 1]] <<- case("d", hdr(0, k - 1), r$eig[k], rel = 1e-8, abs = 1e-12)
  cases[[length(cases) + 1]] <<- case("d", hdr(5, 0), r$rank, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <<- case("d", hdr(6, 0), r$ratio, rel = 1e-8, abs = 1e-12)
  mats <- list(as.matrix(r$c1), as.matrix(r$li), as.matrix(r$co), as.matrix(r$l1))
  for (w in 1:4) { m <- mats[[w]]; v <- as.vector(t(m)); for (k in seq_along(v)) cases[[length(cases) + 1]] <<- case("d", hdr(w, k - 1), v[k], rel = 1e-7, abs = 1e-10) }
}
fc <- c(0, 1, 2, 0, 1, 2, 0, 1, 2)
one2(4, x1, fc, 2); one2(5, x1, fc, 2)
fc6 <- c(0, 1, 0, 1, 0, 1, 2, 2, 2, 0, 1)
x6 <- matrix(rnorm(11 * 6), 11, 6)
one2(4, x6, fc6, 2); one2(5, x6, fc6, 3)
# coinertia of two scaled PCAs: args (6, n, px, nf, what, idx, X table, Y table ncol py = args via nf slot is not free, so py rides first after the table): the layout is
# (6, n, px, nf, what, idx, py, X row-major, Y row-major); what 0 eig, 1 c1, 2 l1, 3 lX, 4 lY, 5 rank, 6 RV
oneci <- function(x, y, nf) {
  n <- nrow(x); px <- ncol(x); py <- ncol(y)
  dx <- dudi.pca(as.data.frame(x), scannf = FALSE, nf = 3); dy <- dudi.pca(as.data.frame(y), scannf = FALSE, nf = 3)
  r <- coinertia(dx, dy, scannf = FALSE, nf = nf)
  flat <- c(py, as.vector(t(x)), as.vector(t(y)))
  hdr <- function(what, idx) c(6, n, px, nf, what, idx, flat)
  for (k in seq_along(r$eig)) cases[[length(cases) + 1]] <<- case("d", hdr(0, k - 1), r$eig[k], rel = 1e-8, abs = 1e-12)
  cases[[length(cases) + 1]] <<- case("d", hdr(5, 0), r$rank, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <<- case("d", hdr(6, 0), r$RV, rel = 1e-8, abs = 1e-12)
  mats <- list(as.matrix(r$c1), as.matrix(r$l1), as.matrix(r$lX), as.matrix(r$lY))
  for (w in 1:4) { m <- mats[[w]]; v <- as.vector(t(m)); for (k in seq_along(v)) cases[[length(cases) + 1]] <<- case("d", hdr(w, k - 1), v[k], rel = 1e-7, abs = 1e-10) }
}
xa <- matrix(rnorm(12 * 4), 12, 4); ya <- matrix(rnorm(12 * 3), 12, 3) + 0.5 * xa[, 1:3]
oneci(xa, ya, 2)
xb <- matrix(rnorm(10 * 3), 10, 3); yb <- matrix(rnorm(10 * 5), 10, 5) + xb[, c(1, 2, 3, 1, 2)]
oneci(xb, yb, 3)
# procuste: (7, n, px, nf, what, idx, py, scale, X row-major, Y row-major); what 0 d[idx], 1 loadX, 2 loadY, 3 scorX, 4 scorY, 5 rank
onepr <- function(x, y, nf, sc) {
  n <- nrow(x); px <- ncol(x); py <- ncol(y)
  r <- procuste(as.data.frame(x), as.data.frame(y), scale = sc, nf = nf)
  flat <- c(py, as.numeric(sc), as.vector(t(x)), as.vector(t(y)))
  hdr <- function(what, idx) c(7, n, px, nf, what, idx, flat)
  for (k in seq_along(r$d)) cases[[length(cases) + 1]] <<- case("d", hdr(0, k - 1), r$d[k], rel = 1e-8, abs = 1e-12)
  cases[[length(cases) + 1]] <<- case("d", hdr(5, 0), r$rank, rel = 0, abs = 0)
  mats <- list(as.matrix(r$loadX), as.matrix(r$loadY), as.matrix(r$scorX), as.matrix(r$scorY))
  for (w in 1:4) { m <- mats[[w]]; v <- as.vector(t(m)); for (k in seq_along(v)) cases[[length(cases) + 1]] <<- case("d", hdr(w, k - 1), v[k], rel = 1e-7, abs = 1e-10) }
}
xp <- matrix(rnorm(15 * 3), 15, 3); yp <- matrix(rnorm(15 * 3), 15, 3) + xp
onepr(xp, yp, 4, TRUE); onepr(xp, yp, 2, FALSE)
xq <- matrix(rnorm(12 * 4), 12, 4); yq <- matrix(rnorm(12 * 2), 12, 2) + xq[, 1:2]
onepr(xq, yq, 4, TRUE)
# dudi.fca: (8, n, p, nf, what, idx, nb, rw (n), table row-major); what 0 eig, 1 c1, 2 li, 3 co, 4 l1, 5 rank
onefca <- function(blocks, n, nf) {
  p <- sum(blocks)
  tab <- matrix(0, n, p); k <- 0
  for (b in blocks) { m <- matrix(runif(n * b), n, b); tab[, k + seq_len(b)] <- m / rowSums(m); k <- k + b }
  rw <- runif(n); rw <- rw / sum(rw)
  df <- as.data.frame(tab)
  names(blocks) <- paste0("v", seq_along(blocks))
  attr(df, "col.blocks") <- blocks; attr(df, "row.w") <- rw; attr(df, "col.num") <- factor(rep(seq_along(blocks), blocks))
  r <- dudi.fca(df, scannf = FALSE, nf = nf)
  flat <- c(length(blocks), rw, as.vector(t(tab)))
  hdr <- function(what, idx) c(8, n, p, nf, what, idx, flat)
  for (k in seq_along(r$eig)) cases[[length(cases) + 1]] <<- case("d", hdr(0, k - 1), r$eig[k], rel = 1e-8, abs = 1e-12)
  cases[[length(cases) + 1]] <<- case("d", hdr(5, 0), r$rank, rel = 0, abs = 0)
  mats <- list(as.matrix(r$c1), as.matrix(r$li), as.matrix(r$co), as.matrix(r$l1))
  for (w in 1:4) { m <- mats[[w]]; v <- as.vector(t(m)); for (k in seq_along(v)) cases[[length(cases) + 1]] <<- case("d", hdr(w, k - 1), v[k], rel = 1e-7, abs = 1e-10) }
}
onefca(c(3, 2, 3), 14, 3)
onefca(c(2, 4), 10, 2)
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
  for (k in seq_along(r$eig)) cases[[length(cases) + 1]] <<- case("d", hdr(0, k - 1), r$eig[k], rel = 1e-8, abs = 1e-12)
  cases[[length(cases) + 1]] <<- case("d", hdr(5, 0), r$rank, rel = 0, abs = 0)
  mats <- list(as.matrix(r$c1), as.matrix(r$l1), as.matrix(r$lR), as.matrix(r$lQ))
  for (w in 1:4) { m <- mats[[w]]; v <- as.vector(t(m)); for (k in seq_along(v)) cases[[length(cases) + 1]] <<- case("d", hdr(w, k - 1), v[k], rel = 1e-7, abs = 1e-10) }
}
onerlq(12, 3, 5, 2, 2)
onerlq(15, 4, 6, 3, 2)
# dudi.mix: (10, n, nv, nf, what, idx, kinds (nv, 0 quantitative, 1 factor), table row-major with 0-based factor codes); what 0 eig, 1 c1, 2 li, 3 co, 4 l1, 5 rank
onemix <- function(n, kinds, nlev, nf) {
  cols <- list(); flat <- matrix(0, n, length(kinds))
  df <- data.frame(row.names = seq_len(n))
  for (j in seq_along(kinds)) {
    if (kinds[j] == 0) { v <- rnorm(n); flat[, j] <- v; df[[paste0("q", j)]] <- v }
    else { f <- sample(0:(nlev[j] - 1), n, TRUE); f[seq_len(nlev[j])] <- 0:(nlev[j] - 1); flat[, j] <- f; df[[paste0("f", j)]] <- factor(f) }
  }
  r <- dudi.mix(df, scannf = FALSE, nf = nf)
  hdr <- function(what, idx) c(10, n, length(kinds), nf, what, idx, kinds, as.vector(t(flat)))
  for (k in seq_along(r$eig)) cases[[length(cases) + 1]] <<- case("d", hdr(0, k - 1), r$eig[k], rel = 1e-8, abs = 1e-12)
  cases[[length(cases) + 1]] <<- case("d", hdr(5, 0), r$rank, rel = 0, abs = 0)
  mats <- list(as.matrix(r$c1), as.matrix(r$li), as.matrix(r$co), as.matrix(r$l1))
  for (w in 1:4) { m <- mats[[w]]; v <- as.vector(t(m)); for (k in seq_along(v)) cases[[length(cases) + 1]] <<- case("d", hdr(w, k - 1), v[k], rel = 1e-7, abs = 1e-10) }
}
onemix(20, c(0, 1, 0, 1), c(0, 3, 0, 4), 3)
onemix(15, c(1, 0, 1), c(2, 0, 3), 2)
emit("ade4_dudi", "ade4", list(cases))
