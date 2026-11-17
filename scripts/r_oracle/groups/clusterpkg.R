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
# ---- clara: its own generator and R's, large and small samples, NA, jaccard, pamLike, correct.d
#   clara_*  args: (n, p, k, samples, sampsize, metric 1 2 3, rngR, seed, pamLike, correct.d, stand, x column-major)
for (rep in 1:48) {
  n <- sample(c(30:60, 80, 120, 200), 1); p <- sample(1:3, 1); k <- sample(2:5, 1)
  metric <- c("euclidean", "manhattan", "jaccard")[if (rep %% 8 == 0) 3 else sample(1:2, 1)]
  samples <- sample(2:8, 1); sampsize <- sample(c(min(n, 40 + 2 * k), k + 1 + sample(0:20, 1), n), 1); sampsize <- min(sampsize, n)
  if (sampsize < k + 1) sampsize <- k + 1
  X <- if (metric == "jaccard") matrix(sample(0:1, n * p, replace = TRUE), n, p)
       else matrix(round(rnorm(n * p) * 3, 2), n, p) + matrix(rep(sample(0:3, n, replace = TRUE) * 4, p), n, p)
  if (rep %% 6 == 0 && metric != "jaccard") X[sample(n * p, max(2, n %/% 8))] <- NA
  rngR <- rep %% 2 == 0; seed <- sample(1:100000, 1); pamLike <- rep %% 3 == 0; correct <- rep %% 4 != 1; stand <- rep %% 5 == 0 && metric != "jaccard"
  res <- try({ if (rngR) set.seed(seed)
    clara(X, k, metric = metric, stand = stand, samples = samples, sampsize = sampsize, rngR = rngR, pamLike = pamLike, correct.d = correct, keep.data = FALSE) }, silent = TRUE)
  if (inherits(res, "try-error")) next
  if (any(res$i.med == 0) || anyNA(res$diss) || anyNA(res$objective)) next  # NaN dissimilarities (jaccard) make the C code read before an array
  a <- c(n, p, k, samples, sampsize, match(metric, c("euclidean", "manhattan", "jaccard")), rngR, seed, pamLike, correct, stand, enc(X))
  add("clara_obj", a, res$objective); add("clara_clu", a, cs(res$clustering)); add("clara_med", a, cs(res$i.med)); add("clara_sample", a, cs(res$sample))
  add("clara_size", a, cs(res$clusinfo[, "size"])); add("clara_maxdis", a, cs(res$clusinfo[, "max_diss"]))
  add("clara_avdis", a, cs(res$clusinfo[, "av_diss"])); add("clara_ratdis", a, cs(res$clusinfo[, "isolation"]))
  add("clara_sil", a, cs(res$silinfo$widths[, "sil_width"])); add("clara_silnb", a, cs(res$silinfo$widths[, "neighbor"]))
  add("clara_avsil", a, cs(res$silinfo$clus.avg.widths)); add("clara_ttsil", a, res$silinfo$avg.width)
}
set.seed(20261118)
emit("clusterpkg", "cluster", list(cases))
