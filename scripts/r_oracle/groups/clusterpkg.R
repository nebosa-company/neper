# cluster 2.1.8.2: pam (every variant, with NA, given and random medoids), clara, fanny, agnes, diana, mona, daisy, silhouette, ellipsoidhull, coef, clusGap.
# Every case is one number: a position-weighted checksum sum(v * seq_along(v)) of a result vector, or a scalar. NA in an input is sent as -999999.
#   pam_*    args: (n, p, k, pamonce, metric, seed, ngiven, given..., x column-major n by p); seed >= 0 draws the medoids with sample.int under set.seed
suppressMessages(library(cluster))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
cs <- function(v) sum(as.numeric(v) * seq_along(v))
enc <- function(x) { x[is.na(x)] <- -999999; as.vector(x) }
set.seed(20261117)

# ---- pam: variants, metrics, NA, ties
VARS <- c("original", "o_1", "o_2", "f_3", "f_4", "f_5", "faster")
for (rep in 1:70) {
  n <- sample(c(6:14, 20, 30, 45), 1); p <- sample(1:3, 1); k <- sample(1:min(6, n - 1), 1)
  metric <- sample(c("euclidean", "manhattan"), 1)
  X <- matrix(round(rnorm(n * p) * 3, sample(1:2, 1)), n, p) + matrix(rep(sample(0:3, n, replace = TRUE) * 3, p), n, p)
  if (rep %% 7 == 0) X[sample(n * p, max(1, n %/% 4))] <- NA
  if (any(rowSums(!is.na(X)) == 0)) next
  vi <- (rep %% 7) + 1; variant <- VARS[vi]
  hasgiven <- (rep %% 3 == 0) && variant != "faster"
  given <- if (hasgiven) sort(sample(n, k)) else integer(0)
  seed <- if (variant == "faster") sample(1:100000, 1) else -1
  res <- try({
    if (variant == "faster") { set.seed(seed); pam(X, k, metric = metric, variant = variant, keep.diss = FALSE, keep.data = FALSE) }
    else if (hasgiven) pam(X, k, metric = metric, variant = variant, medoids = given, keep.diss = FALSE, keep.data = FALSE)
    else pam(X, k, metric = metric, variant = variant, keep.diss = FALSE, keep.data = FALSE)
  }, silent = TRUE)
  if (inherits(res, "try-error")) next
  a <- c(n, p, k, vi - 1, if (metric == "euclidean") 1 else 2, seed, length(given), given, enc(X))
  add("pam_build", a, res$objective[1]); add("pam_swap", a, res$objective[2])
  add("pam_med", a, cs(res$id.med)); add("pam_clu", a, cs(res$clustering))
  add("pam_isol", a, cs(as.integer(res$isolation) - 1))
  add("pam_clusinf", a, cs(as.vector(res$clusinfo)))
  if (k > 1) {
    add("pam_sil", a, cs(res$silinfo$widths[, "sil_width"]))
    add("pam_silnb", a, cs(res$silinfo$widths[, "neighbor"]))
    add("pam_avsil", a, cs(res$silinfo$clus.avg.widths))
    add("pam_ttsil", a, res$silinfo$avg.width)
  }
}
set.seed(20261118)
emit("clusterpkg", "cluster", list(cases))
