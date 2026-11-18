# ade4 dudi.pca and dudi.coa. Args: (kind, n, p, nf, what, idx, table row-major...): kind 0 dudi.pca (scaled), 1 dudi.pca (centred only), 2 dudi.coa;
# what 0 is eig[idx], 1 c1, 2 li, 3 co, 4 l1 (row-major, nf columns), 5 the rank (idx unused).
suppressMessages(library(ade4))
cases <- list()
set.seed(20261501)
one <- function(kind, x, nf) {
  n <- nrow(x); p <- ncol(x)
  d <- as.data.frame(x)
  r <- switch(kind + 1, dudi.pca(d, scannf = FALSE, nf = nf), dudi.pca(d, scale = FALSE, scannf = FALSE, nf = nf), dudi.coa(d, scannf = FALSE, nf = nf))
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
emit("ade4_dudi", "ade4", list(cases))
