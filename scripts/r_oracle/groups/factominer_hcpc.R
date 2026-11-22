# FactoMineR HCPC (graph = FALSE, description = FALSE) on the individuals of a weighted PCA: the Ward tree on the sorted coordinates (merge, order, heights),
# the number of clusters (given or chosen by the inertia-gain criterion over min..max), the partition with and without k-means consolidation, centres, quotients.
#   args: blk, n, p, ncp, scale, nb (0 = auto), consol, minc, maxc (0 = default), rw[n], x[n*p] (row-major)
#   blocks: 0 nb.clust, 1 clust, 2 tree height, 3 merge a, 4 merge b, 5 order, 6 centres (by row), 7 quot, 8 inertia gain, 9 perm of the sorted rows
suppressMessages(library(FactoMineR))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("blk", args, want, rel = 1e-9, abs = 1e-11)
ws <- function(v) sum(as.vector(v) * seq_along(v))
rowmajor <- function(m) as.vector(t(m))
set.seed(20261231)
for (rep in 1:20) {
  n <- sample(12:45, 1); p <- sample(3:6, 1)
  scale <- rep %% 3 != 0; consol <- rep %% 2 == 0
  nb <- if (rep %% 4 < 2) 0 else sample(2:5, 1)
  minc <- sample(2:4, 1); maxc <- if (rep %% 5 == 0) sample(5:8, 1) else 0
  x <- matrix(rnorm(n * p), n); x <- x + matrix(rep(sample(0:3, n, replace = TRUE) * 2, p), n); x[, 2] <- x[, 1] + 0.4 * x[, 2]
  x <- x * rep(c(1, 3, 0.5, 2, 1, 4)[1:p], each = n) + 2
  rw <- if (rep %% 3 == 1) sample(1:4, n, replace = TRUE) else rep(1, n)
  df <- data.frame(x); names(df) <- paste0("V", 1:p)
  f <- PCA(df, row.w = rw, scale.unit = scale, ncp = 5, graph = FALSE)
  h <- HCPC(f, nb.clust = if (nb == 0) -1 else nb, consol = consol, min = minc, max = if (maxc == 0) NULL else maxc, graph = FALSE, description = FALSE)
  tt <- h$call$t
  a <- c(n, p, 5, as.numeric(scale), nb, as.numeric(consol), minc, maxc, rw, rowmajor(x))
  cl <- as.numeric(as.character(h$data.clust$clust))
  centres <- t(sapply(sort(unique(cl)), function(k) colMeans(f$ind$coord[cl == k, , drop = FALSE])))
  blocks <- list(`0` = max(cl), `1` = cl, `2` = tt$tree$height, `3` = tt$tree$merge[, 1], `4` = tt$tree$merge[, 2], `5` = tt$tree$order,
                 `6` = rowmajor(centres),
                 `7` = tt$quot, `8` = tt$inert.gain, `9` = match(rownames(tt$res$ind$coord), rownames(f$ind$coord)))
  for (b in names(blocks)) add(c(as.numeric(b), a), ws(blocks[[b]]))
}
emit("factominer_hcpc", "FactoMineR", list(cases))
