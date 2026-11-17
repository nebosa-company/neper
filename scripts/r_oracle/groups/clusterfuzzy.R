# cluster 2.1.8.2: fanny (memb.exp, metrics, stand, NA, given initial memberships, a dist input, maxit and tol), ellipsoidhull and clusGap.
# Every case is one number: a position-weighted checksum sum(v * seq_along(v)) of a result vector, or a scalar. NA in an input is sent as -999999.
suppressMessages(library(cluster))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
cs <- function(v) sum(as.numeric(v) * seq_along(v))
enc <- function(x) { x[is.na(x)] <- -999999; as.vector(x) }
set.seed(20261121)
#   fanny_*  args: (n, p, k, metric 1 2 3, stand, memb.exp, tol, maxit, hasini, diss, x column-major (n by p), ini column-major (n by k) when hasini)
for (rep in 1:60) {
  n <- sample(c(8:16, 25, 40), 1); p <- sample(1:3, 1); k <- sample(1:max(1, n %/% 2 - 1), 1); k <- min(k, 4)
  metric <- sample(c("euclidean", "manhattan", "SqEuclidean"), 1); stand <- rep %% 6 == 0
  r <- sample(c(2, 2, 1.5, 3), 1); tol <- sample(c(1e-15, 1e-9, 1e-6), 1); maxit <- sample(c(500, 500, 500, 6), 1)
  diss <- rep %% 5 == 0; if (diss) metric <- "euclidean"
  X <- matrix(round(rnorm(n * p) * 3, 3), n, p) + matrix(rep(sample(0:2, n, replace = TRUE) * 4, p), n, p)
  if (rep %% 7 == 0 && !diss) X[sample(n * p, max(1, n %/% 6))] <- NA
  if (any(rowSums(!is.na(X)) == 0)) next
  hasini <- rep %% 4 == 0 && k >= 2
  ini <- if (hasini) { m <- matrix(runif(n * k) + 0.05, n, k); m / rowSums(m) } else NULL
  f <- try(suppressWarnings(if (diss) fanny(dist(X), k, diss = TRUE, memb.exp = r, iniMem.p = ini, maxit = maxit, tol = tol, keep.diss = FALSE)
           else fanny(X, k, metric = metric, stand = stand, memb.exp = r, iniMem.p = ini, maxit = maxit, tol = tol, keep.diss = FALSE, keep.data = FALSE)), silent = TRUE)
  if (inherits(f, "try-error")) next
  a <- c(n, p, k, match(metric, c("euclidean", "manhattan", "SqEuclidean")), stand, r, tol, maxit, hasini, diss, enc(X), if (hasini) as.vector(ini))
  add("fanny_memb", a, cs(as.vector(f$membership))); add("fanny_dunn", a, f$coeff[["dunn_coeff"]]); add("fanny_norm", a, f$coeff[["normalized"]])
  add("fanny_obj", a, f$objective[["objective"]]); add("fanny_kcrisp", a, f$k.crisp); add("fanny_clu", a, cs(f$clustering))
  add("fanny_iter", a, f$convergence[["iterations"]])
  if (!is.null(f$silinfo) && f$k.crisp >= 2 && f$k.crisp < n) {
    add("fanny_sil", a, cs(f$silinfo$widths[, "sil_width"])); add("fanny_silnb", a, cs(f$silinfo$widths[, "neighbor"]))
    add("fanny_avsil", a, cs(f$silinfo$clus.avg.widths[seq_len(f$k.crisp)])); add("fanny_ttsil", a, f$silinfo$avg.width)
  }
}
emit("clusterfuzzy", "cluster", list(cases))
