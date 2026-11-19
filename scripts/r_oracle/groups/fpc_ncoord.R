# fpc::ncoord with sphere = "none" or a given covariance matrix. Args: (n, p, k, nn, weighted, sphered, what, idx, x row-major, cl 0-based [n], then the p by p covariance row-major):
# what 0 ev[idx], 1 units[idx] (row-major p by p, so signs count), 2 proj[idx] (row-major n by p); only the first k - 1 axes are compared, each normalised in sign (see below).
suppressMessages(library(fpc))
cases <- list()
set.seed(20262102)
for (rep in 1:8) {
  p <- sample(2:4, 1); k <- sample(2:3, 1); m <- sample(18:30, k, replace = TRUE); n <- sum(m)
  ctr <- matrix(rnorm(k * p, 0, 2), k, p)
  x <- do.call(rbind, lapply(seq_len(k), function(g) matrix(rnorm(m[g] * p), m[g], p) + rep(ctr[g, ], each = m[g])))
  x <- round(x, 4); cl <- rep(seq_len(k), m)
  nn <- c(10, 15, 20)[rep %% 3 + 1]; wtd <- rep %% 2 == 1; sph <- rep %% 4 >= 2
  cvm <- if (sph) cov(x) else diag(p)
  r <- if (sph) ncoord(x, cl, nn = nn, weighted = wtd, sphere = cvm, countmode = 100000) else ncoord(x, cl, nn = nn, weighted = wtd, sphere = "none", countmode = 100000)
  hdr <- function(w, i) c(n, p, k, nn, as.numeric(wtd), as.numeric(sph), w, i, as.vector(t(x)), cl - 1, as.vector(t(cvm)))
  add <- function(w, i, v) cases[[length(cases) + 1]] <<- case("nc", hdr(w, i), v, rel = 1e-6, abs = 1e-8)
  for (i in seq_len(p)) add(0, i - 1, r$ev[i])
  # B has rank at most k - 1, so only the first k - 1 axes are determined (the others are arbitrary null directions)
  # axis signs: R and the port can differ in the sign of an eigenvector (LAPACK's choice flips with the last bits), so each axis is normalised to a positive largest-magnitude entry of its direction
  sg <- vapply(seq_len(k - 1), function(cc) sign(r$units[which.max(abs(r$units[, cc])), cc]), 0)
  for (rr in seq_len(p)) for (cc in seq_len(k - 1)) add(1, (rr - 1) * p + cc - 1, sg[cc] * r$units[rr, cc])
  for (ii in seq_len(n)) for (cc in seq_len(k - 1)) add(2, (ii - 1) * p + cc - 1, sg[cc] * r$proj[ii, cc])
}
emit("fpc_ncoord", "fpc", list(cases))
