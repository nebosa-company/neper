# cluster::pam against e.algo.stat.clusterpam, every pamonce variant, given and random medoids, do.swap, stand, manhattan,
# missing values and a dissimilarity input.
#   args: (n, p, k, pamonce, doswap, metric, stand, seed, nstart, diss, nmed, med[1..nmed], data)
#     data is x row-major (NA as -999999), or the R dist vector of the n objects when diss is 1; seed > 0 draws the starting medoids
#     with sample.int under set.seed(seed) (nstart starts, the best swap objective wins)
#   fn names the answer: obj0 and obj1 (build and swap objectives), then position-weighted sums of med (id.med), clu (clustering),
#     isol (isolation, 0 no / 1 L / 2 L*), cs1..cs5 (clusinfo columns), sil1..sil3 (silinfo widths columns), sil4 (the observation
#     numbers of the widths rows), avsil (clus.avg.widths) and the plain ttsil (avg.width)
suppressMessages(library(cluster))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
wsum <- function(v) sum(as.numeric(v) * seq_along(v))
set.seed(20270102)

onepam <- function(x, k, pamonce, doswap, metric, stand, med = NULL, seed = 0, nstart = 1, diss = FALSE) {
  n <- if (diss) attr(x, "Size") else nrow(x)
  p <- if (diss) 1 else ncol(x)
  data <- if (diss) as.vector(x) else as.vector(t(ifelse(is.na(x), -999999, x)))
  head <- c(n, p, k, pamonce, doswap, metric, stand, seed, nstart, diss, length(med), med)
  a <- c(head, data)
  call <- function() {
    if (seed > 0) set.seed(seed)
    if (diss) {
      if (seed > 0) pam(x, k, diss = TRUE, medoids = "random", nstart = nstart, do.swap = doswap, pamonce = pamonce)
      else pam(x, k, diss = TRUE, medoids = med, do.swap = doswap, pamonce = pamonce)
    } else {
      m <- c("euclidean", "manhattan")[metric]
      if (seed > 0) pam(x, k, metric = m, stand = stand, medoids = "random", nstart = nstart, do.swap = doswap, pamonce = pamonce)
      else pam(x, k, metric = m, stand = stand, medoids = med, do.swap = doswap, pamonce = pamonce)
    }
  }
  p <- tryCatch(suppressWarnings(call()), error = function(e) NULL)
  if (is.null(p)) return(invisible())
  add("obj0", a, p$objective[1]); add("obj1", a, p$objective[2])
  add("med", a, wsum(p$id.med), 0, 0)
  add("clu", a, wsum(p$clustering), 0, 0)
  add("isol", a, wsum(as.integer(p$isolation) - 1L), 0, 0)
  for (j in 1:5) add(paste0("cs", j), a, wsum(p$clusinfo[, j]))
  if (k > 1) {
    w <- p$silinfo$widths
    add("sil1", a, wsum(w[, 1]), 0, 0); add("sil2", a, wsum(w[, 2]), 0, 0); add("sil3", a, wsum(w[, 3]))
    add("sil4", a, wsum(as.integer(rownames(w))), 0, 0)
    add("avsil", a, wsum(p$silinfo$clus.avg.widths)); add("ttsil", a, p$silinfo$avg.width)
  }
}

gen <- function(n, p, grid, na = 0) {
  g <- sample(2:4, 1)
  x <- matrix(rnorm(n * p) * 2, n, p) + matrix(rep(sample(0:(g - 1), n, replace = TRUE) * 5, p), n, p)
  x <- if (grid) round(x * 4) / 4 else round(x, 6)
  if (na > 0) { idx <- sample(n * p, na); x[idx] <- NA; for (i in which(rowSums(!is.na(x)) == 0)) x[i, 1] <- 1 }
  x
}

# every variant, continuous and tie-prone data
for (po in 0:6) for (rep in 1:7) {
  n <- sample(8:26, 1); p <- sample(1:3, 1); k <- sample(2:5, 1)
  x <- gen(n, p, rep %% 2 == 0)
  onepam(x, k, po, 1, sample(1:2, 1), 0)
}
# k = 1, do.swap = FALSE, standardised and missing values
for (po in c(0, 6)) {
  x <- gen(14, 2, FALSE); onepam(x, 1, po, 1, 1, 0)
}
for (rep in 1:6) {
  x <- gen(sample(10:24, 1), 2, rep %% 2 == 0); onepam(x, sample(2:4, 1), sample(0:6, 1), 0, 1, 0)
}
for (rep in 1:8) {
  x <- gen(sample(10:30, 1), 3, FALSE); onepam(x, sample(2:5, 1), sample(0:6, 1), 1, sample(1:2, 1), 1)
}
for (rep in 1:10) {
  n <- sample(12:28, 1); x <- gen(n, 3, rep %% 2 == 0, na = sample(2:6, 1)); onepam(x, sample(2:4, 1), sample(0:6, 1), 1, sample(1:2, 1), rep %% 2)
}
# starting medoids given
for (rep in 1:14) {
  n <- sample(10:26, 1); k <- sample(2:5, 1); x <- gen(n, 2, rep %% 2 == 0)
  onepam(x, k, sample(0:6, 1), sample(0:1, 1), 1, 0, med = sample.int(n, k))
}
# random starts: variant "faster" and the others
for (rep in 1:14) {
  n <- sample(10:30, 1); k <- sample(2:5, 1); x <- gen(n, 2, rep %% 2 == 0); sd <- sample(1:100000, 1)
  onepam(x, k, if (rep <= 7) 6 else sample(0:5, 1), 1, 1, 0, seed = sd, nstart = sample(1:4, 1))
}
# a dissimilarity as input
for (rep in 1:10) {
  n <- sample(8:22, 1); k <- sample(2:5, 1)
  v <- if (rep %% 2) round(runif(n * (n - 1) / 2, 0.5, 9) * 4) / 4 else runif(n * (n - 1) / 2, 0.5, 9)
  d <- structure(v, Size = n, class = "dist")
  onepam(d, k, sample(0:6, 1), 1, 1, 0, diss = TRUE)
}
emit("clusterpam", "cluster", list(cases))
