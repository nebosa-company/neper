# stats::varimax (normalize = TRUE, eps 1e-5) and stats::promax(m): the loadings and the rotation matrix, row-major.
#   args: (kind 0 varimax 1 promax, p, k, m, loadings row-major[p*k], q)  q 0..p*k-1 rotated loadings, then k*k rotation matrix entries
cases <- list()
set.seed(20261116)
for (rep in 1:30) {
  p <- sample(5:12, 1); k <- sample(2:4, 1); m <- c(2, 3, 4, 5)[rep %% 4 + 1]
  L <- matrix(rnorm(p * k) * 0.5, p, k); for (j in 1:k) { idx <- sample(p, ceiling(p / k)); L[idx, j] <- L[idx, j] + runif(length(idx), 0.5, 1.2) }
  L <- round(L, 3)
  for (kind in 0:1) {
    r <- if (kind == 0) varimax(L) else promax(L, m = m)
    ld <- unclass(r$loadings); rm <- r$rotmat
    out <- c(as.vector(t(ld)), as.vector(t(rm)))
    for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("rot", c(kind, p, k, m, as.vector(t(L)), q - 1), out[q], rel = 1e-6, abs = 1e-7)
  }
}
emit("promax", character(), list(cases))
