# cluster 2.1.8.2: pam (every variant, with NA, given and random medoids), clara, daisy and silhouette (agnes, diana and mona are in clustertree.R).
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
# ---- daisy: mixed types, weights, gower, logratio, ordratio, asymmetric and symmetric binary, NA, stand
#   daisy_*  args: (n, p, metric 1 2 3, stand, types(p) 1 A 2 S 3 N 4 O 5 I 6 T 7 logratio, weights(p), x column-major codes with NA = -999999)
for (rep in 1:60) {
  n <- sample(5:25, 1); p <- sample(1:5, 1)
  ty <- sample(c(5, 5, 3, 4, 1, 2, 6, 7), p, replace = TRUE)
  allI <- all(ty == 5)
  if (rep %% 4 == 0) ty[] <- 5
  df <- data.frame(row.names = seq_len(n)); typ <- list(asymm = integer(0), symm = integer(0), ordratio = integer(0), logratio = integer(0))
  for (j in 1:p) {
    v <- switch(as.character(ty[j]),
      "5" = round(rnorm(n) * 3, 2), "7" = round(exp(rnorm(n)), 3), "6" = sample(c(1, 2, 3, 5, 8), n, replace = TRUE),
      "3" = factor(sample(c("a", "b", "c"), n, replace = TRUE)), "4" = factor(sample(c("lo", "mid", "hi"), n, replace = TRUE), levels = c("lo", "mid", "hi"), ordered = TRUE),
      "1" = sample(0:1, n, replace = TRUE), "2" = sample(0:1, n, replace = TRUE))
    if (rep %% 3 == 0) v[sample(n, 1)] <- NA
    df[[j]] <- v
    if (ty[j] == 1) typ$asymm <- c(typ$asymm, j); if (ty[j] == 2) typ$symm <- c(typ$symm, j)
    if (ty[j] == 6) typ$ordratio <- c(typ$ordratio, j); if (ty[j] == 7) typ$logratio <- c(typ$logratio, j)
  }
  typ <- typ[lengths(typ) > 0]
  w <- if (rep %% 2 == 0) round(runif(p, 0.5, 2), 2) else rep(1, p)
  metric <- sample(c("euclidean", "manhattan", "gower"), 1); stand <- rep %% 5 == 0
  d <- try(suppressWarnings(daisy(df, metric = metric, stand = stand, type = typ, weights = w)), silent = TRUE)
  if (inherits(d, "try-error") || anyNA(d)) next
  M <- data.matrix(df)
  a <- c(n, p, match(metric, c("euclidean", "manhattan", "gower")), stand, ty, w, enc(M))
  add("daisy_lower", a, cs(as.vector(d)))
}
# ---- silhouette on a clustering and a dissimilarity (matrix and dist vector)
#   sil_*  args: (n, k, ismat, cluster(n), x(n by 2, column-major))
for (rep in 1:30) {
  n <- sample(6:40, 1); k <- sample(2:min(6, n - 1), 1)
  X <- matrix(round(rnorm(n * 2) * 3, 3), n, 2); cl <- sample(rep(1:k, length.out = n))
  ismat <- rep %% 2 == 0
  s <- if (ismat) silhouette(cl, dmatrix = as.matrix(dist(X))) else silhouette(cl, dist(X))
  a <- c(n, k, ismat, cl, as.vector(X))
  add("sil_width", a, cs(s[, "sil_width"])); add("sil_nb", a, cs(s[, "neighbor"]))
}
set.seed(20261118)
emit("clusterpkg", "cluster", list(cases))
