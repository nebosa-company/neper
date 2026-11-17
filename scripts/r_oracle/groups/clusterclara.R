# cluster::clara against e.algo.stat.clusterpam.clara_core: the package's own sampling generator and R's (rngR), full and large
# samples, the three metrics, standardisation, missing values, pamLike and correct.d.
#   args: (n, p, k, samples, sampsize, metric, stand, rngR, seed, pamLike, correctd, data)   metric 1 euclidean 2 manhattan 3 jaccard
#     data is x row-major, NA as -999999; fn names the answer: sample, imed, clu (position-weighted sums of the sample, the
#     medoid numbers, the clustering), obj, size, maxdis, avdis, ratdis (clusinfo columns, position-weighted), sil1..sil4
#     (silinfo widths columns and the observation numbers of its rows, position-weighted), avsil and ttsil
suppressMessages(library(cluster))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
wsum <- function(v) sum(as.numeric(v) * seq_along(v))
set.seed(20270103)

oneclara <- function(x, k, samples, sampsize, metric, stand, rngR, seed, pamLike, correctd) {
  n <- nrow(x); p <- ncol(x)
  a <- c(n, p, k, samples, sampsize, metric, stand, rngR, seed, pamLike, correctd, as.vector(t(ifelse(is.na(x), -999999, x))))
  m <- c("euclidean", "manhattan", "jaccard")[metric]
  set.seed(seed)
  r <- tryCatch(suppressWarnings(clara(x, k, metric = m, stand = stand == 1, samples = samples, sampsize = sampsize, rngR = rngR == 1,
                                       pamLike = pamLike == 1, correct.d = correctd == 1)), error = function(e) NULL)
  if (is.null(r)) return(invisible())
  add("sample", a, wsum(r$sample), 0, 0); add("imed", a, wsum(r$i.med), 0, 0); add("clu", a, wsum(r$clustering), 0, 0)
  add("obj", a, r$objective)
  add("size", a, wsum(r$clusinfo[, 1]), 0, 0); add("maxdis", a, wsum(r$clusinfo[, 2])); add("avdis", a, wsum(r$clusinfo[, 3]))
  add("ratdis", a, wsum(r$clusinfo[, 4]))
  if (k > 1) {
    w <- r$silinfo$widths
    add("sil1", a, wsum(w[, 1]), 0, 0); add("sil2", a, wsum(w[, 2]), 0, 0); add("sil3", a, wsum(w[, 3]))
    add("sil4", a, wsum(as.integer(rownames(w))), 0, 0)
    add("avsil", a, wsum(r$silinfo$clus.avg.widths)); add("ttsil", a, r$silinfo$avg.width)
  }
}

gen <- function(n, p, na = 0, binary = FALSE) {
  g <- sample(2:4, 1)
  x <- matrix(rnorm(n * p) * 2, n, p) + matrix(rep(sample(0:(g - 1), n, replace = TRUE) * 5, p), n, p)
  x <- round(x * 16) / 16
  if (binary) x <- matrix(rbinom(n * p, 1, 0.45), n, p)
  if (na > 0) { idx <- sample(n * p, na); x[idx] <- NA; for (i in which(rowSums(!is.na(x)) == 0)) x[i, 1] <- 1 }
  x
}

# sampling from the package's generator: small samples, large samples (n < 2 sampsize), the full sample
for (rep in 1:14) {
  n <- sample(24:90, 1); p <- sample(1:3, 1); k <- sample(2:4, 1)
  ss <- if (rep <= 5) sample((k + 1):max(k + 2, n %/% 3), 1) else if (rep <= 10) sample((n %/% 2 + 1):(n - 1), 1) else if (rep <= 12) n else sample((k + 1):15, 1)
  oneclara(gen(n, p), k, sample(2:6, 1), ss, sample(1:2, 1), rep %% 2, 0, 1, 0, 1)
}
# R's generator
for (rep in 1:14) {
  n <- sample(30:90, 1); p <- sample(1:3, 1); k <- sample(2:4, 1)
  ss <- if (rep <= 10) sample((k + 1):max(k + 2, n %/% 3), 1) else sample((n %/% 2 + 1):(n - 1), 1)
  oneclara(gen(n, p), k, sample(2:6, 1), ss, sample(1:2, 1), 0, 1, sample(1:100000, 1), rep %% 2, 1)
}
# jaccard
for (rep in 1:5) {
  n <- sample(30:70, 1); k <- sample(2:3, 1)
  oneclara(gen(n, sample(4:6, 1), binary = TRUE), k, 4, sample((k + 2):20, 1), 3, 0, rep %% 2, 7 + rep, 0, 1)
}
# missing values with both distance formulas
for (rep in 1:10) {
  n <- sample(30:80, 1); k <- sample(2:3, 1)
  oneclara(gen(n, 3, na = sample(3:12, 1)), k, sample(2:5, 1), sample((k + 2):25, 1), sample(1:2, 1), rep %% 2, rep %% 2, 30 + rep, 0, rep %% 3 != 0)
}
# k = 1
oneclara(gen(40, 2), 1, 3, 12, 1, 0, 0, 1, 0, 1)
emit("clusterclara", "cluster", list(cases))
