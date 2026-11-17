# cluster 2.1.8.2: ellipsoidhull (loc, cov, d2, eps, iterations, convergence, volume) and clusGap with pam (both spaceH0, d.power, seeded reference draws) and maxSE.
# Every case is one number: a position-weighted checksum sum(v * seq_along(v)) of a result vector, or a scalar.
suppressMessages(library(cluster))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
cs <- function(v) sum(as.numeric(v) * seq_along(v))
set.seed(20261122)
#   hull_*  args: (n, p, tol, maxit, x column-major)
for (rep in 1:24) {
  n <- sample(8:50, 1); p <- sample(2:3, 1)
  X <- matrix(rnorm(n * p) * sample(1:4, p, replace = TRUE), n, p) + matrix(rep(rnorm(p, 0, 5), each = n), n, p)
  tol <- sample(c(0.01, 0.001, 1e-5), 1); maxit <- sample(c(5000, 5000, 12), 1)
  e <- try(suppressWarnings(ellipsoidhull(X, tol = tol, maxit = maxit, ret.sqdist = TRUE)), silent = TRUE)
  if (inherits(e, "try-error") || e$ierr != 0) next
  a <- c(n, p, tol, maxit, as.vector(X))
  add("hull_loc", a, cs(e$loc)); add("hull_cov", a, cs(as.vector(e$cov))); add("hull_d2", a, e$d2); add("hull_eps", a, e$eps)
  add("hull_it", a, e$it); add("hull_conv", a, as.numeric(e$conv)); add("hull_logvol", a, volume(e, log = TRUE))
}
#   gap_*  args: (n, p, K.max, B, d.power, pca, seed, x column-major)
METHODS <- c("firstSEmax", "Tibs2001SEmax", "globalSEmax", "firstmax", "globalmax")
for (rep in 1:16) {
  n <- sample(12:30, 1); p <- sample(1:3, 1); kmax <- sample(2:5, 1); B <- sample(5:14, 1); dp <- sample(c(1, 2), 1); pca <- rep %% 2 == 0
  X <- matrix(rnorm(n * p) * 2, n, p) + matrix(rep(sample(0:2, n, replace = TRUE) * 4, p), n, p)
  seed <- sample(1:100000, 1)
  set.seed(seed)
  g <- try(clusGap(X, function(x, k) list(cluster = pam(x, k, keep.diss = FALSE, keep.data = FALSE)$clustering), K.max = kmax, B = B, d.power = dp,
                   spaceH0 = if (pca) "scaledPCA" else "original", verbose = FALSE), silent = TRUE)
  if (inherits(g, "try-error")) next
  a <- c(n, p, kmax, B, dp, pca, seed, as.vector(X))
  add("gap_logw", a, cs(g$Tab[, "logW"])); add("gap_elogw", a, cs(g$Tab[, "E.logW"])); add("gap_gap", a, cs(g$Tab[, "gap"])); add("gap_se", a, cs(g$Tab[, "SE.sim"]))
  for (m in 1:5) add(paste0("gap_maxse", m), a, maxSE(g$Tab[, "gap"], g$Tab[, "SE.sim"], method = METHODS[m]))
}
emit("clusterhull", "cluster", list(cases))
