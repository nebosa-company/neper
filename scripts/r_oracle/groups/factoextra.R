# factoextra (get_eigenvalue, get_pca_var, get_pca_ind, hcut, fviz_nbclust over hcut) and NbClust indices.
#   every case is the position-weighted sum of one result block; args begin (kind, block, ...), x row-major
#   kind 0 get_*: n, p, scale, x      blocks: 0 get_eigenvalue (rows by 3), 1-4 get_pca_var coord cor cos2 contrib, 5-7 get_pca_ind coord cos2 contrib
#   kind 1 hcut: n, p, k, method, metric, stand, x   blocks: 0 cluster, 1 size, 2 silhouette widths, 3 neighbour, 4 cluster avg widths, 5 avg width, 6 merge a, 7 merge b, 8 height, 9 order
#   kind 2 fviz_nbclust: n, p, kmax, method, x   blocks: 0 wss (k = 1..kmax), 1 silhouette (k = 2..kmax)   [hcut on the euclidean distance]
#   kind 3 NbClust: n, p, method, metric, minc, maxc, x   blocks: 0-29 the column of All.index (R order), 100 + column the number of clusters that index picks (KL CH DB Silhouette Ptbiserial McClain Gamma Gplus Tau)
#   method codes are e.algo.stat.hclust's: 1 ward.D 2 single 3 complete 4 average 5 mcquitty 6 median 7 centroid 8 ward.D2; metric 0 euclidean 1 maximum 2 manhattan 3 pearson
suppressMessages({ library(FactoMineR); library(factoextra); library(NbClust) })
# NbClust rounds All.index to 4 digits; this copy keeps the unrounded table (nothing else changes)
nbsrc <- paste(deparse(NbClust::NbClust), collapse = "\n")
nbsrc <- sub("res <- round(res, digits = 4)", "res <- res", nbsrc, fixed = TRUE)
nbsrc <- sub("resultats <- round(resultats, digits = 4)", "resultats <- resultats", nbsrc, fixed = TRUE)
NbClustX <- eval(parse(text = nbsrc)); environment(NbClustX) <- asNamespace("NbClust")
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("blk", args, want, rel = 1e-9, abs = 1e-11)
ws <- function(v) sum(as.vector(v) * seq_along(v))
rowmajor <- function(m) as.vector(t(m))
mnames <- c("ward.D", "single", "complete", "average", "mcquitty", "median", "centroid", "ward.D2")
dnames <- c("euclidean", "maximum", "manhattan", "pearson")
mkdata <- function(n, p) {
  x <- matrix(rnorm(n * p), n) + matrix(rep(sample(0:3, n, replace = TRUE) * 2.5, p), n)
  x <- x * rep(c(1, 3, 0.5, 2, 1, 4)[1:p], each = n) + 2
  rownames(x) <- seq_len(n); colnames(x) <- paste0("V", seq_len(p)); x
}
set.seed(20270101)
# kind 0
for (rep in 1:6) {
  n <- sample(12:40, 1); p <- sample(3:6, 1); sc <- rep %% 2 == 0
  x <- mkdata(n, p)
  f <- PCA(as.data.frame(x), scale.unit = sc, ncp = p, graph = FALSE)
  a <- c(0, n, p, as.numeric(sc), rowmajor(x))
  v <- get_pca_var(f); i <- get_pca_ind(f)
  blocks <- list(get_eigenvalue(f), v$coord, v$cor, v$cos2, v$contrib, i$coord, i$cos2, i$contrib)
  for (b in seq_along(blocks)) add(c(a[1], b - 1, a[-1]), ws(rowmajor(blocks[[b]])))
}
# kind 1
for (rep in 1:16) {
  n <- sample(12:40, 1); p <- sample(2:5, 1); k <- sample(2:6, 1)
  m <- ((rep - 1) %% 8) + 1; met <- sample(0:3, 1); st <- rep %% 3 == 0
  x <- mkdata(n, p)
  h <- hcut(x, k = k, hc_method = mnames[m], hc_metric = dnames[met + 1], stand = st)
  w <- h$silinfo$widths[rownames(x), ]
  a <- c(1, n, p, k, m, met, as.numeric(st), rowmajor(x))
  blocks <- list(h$cluster, h$size, w$sil_width, w$neighbor, h$silinfo$clus.avg.widths, h$silinfo$avg.width,
                 h$merge[, 1], h$merge[, 2], h$height, h$order)
  for (b in seq_along(blocks)) add(c(a[1], b - 1, a[-1]), ws(blocks[[b]]))
}
# kind 2
for (rep in 1:8) {
  n <- sample(15:40, 1); p <- sample(2:5, 1); kmax <- sample(5:9, 1); m <- c(1, 2, 3, 4, 5, 8, 4, 3)[rep]
  x <- mkdata(n, p)
  a <- c(2, n, p, kmax, m, rowmajor(x))
  pw <- fviz_nbclust(x, hcut, method = "wss", k.max = kmax, hc_method = mnames[m])
  ps <- fviz_nbclust(x, hcut, method = "silhouette", k.max = kmax, hc_method = mnames[m])
  add(c(a[1], 0, a[-1]), ws(pw$data$y))
  add(c(a[1], 1, a[-1]), ws(ps$data$y))
}
# kind 3
for (rep in 1:10) {
  n <- sample(18:40, 1); p <- sample(3:5, 1); minc <- sample(2:3, 1); maxc <- minc + sample(4:6, 1)
  m <- c(8, 1, 3, 4, 2, 5, 8, 3, 4, 8)[rep]; met <- c(0, 0, 0, 2, 0, 1, 2, 0, 0, 1)[rep]
  x <- mkdata(n, p)
  r <- tryCatch(suppressWarnings(capture.output(nb <- NbClustX(x, distance = dnames[met + 1], min.nc = minc, max.nc = maxc, method = mnames[m], index = "alllong"))), error = function(e) NULL)
  if (is.null(r)) next
  a <- c(3, n, p, m, met, minc, maxc, rowmajor(x))
  all <- as.matrix(nb$All.index)
  cn <- c("KL", "CH", "Hartigan", "CCC", "Scott", "Marriot", "TrCovW", "TraceW", "Friedman", "Rubin", "Cindex", "DB", "Silhouette", "Duda", "Pseudot2", "Beale", "Ratkowsky", "Ball", "Ptbiserial", "Gap", "Frey", "McClain", "Gamma", "Gplus", "Tau", "Dunn", "Hubert", "SDindex", "Dindex", "SDbw")
  for (col in 1:30) {
    if (!(cn[col] %in% colnames(all))) next
    v <- all[, cn[col]]
    if (any(!is.finite(v))) next
    add(c(a[1], col - 1, a[-1]), ws(v))
    if (col %in% c(1, 2, 3, 4, 5, 6, 20, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 22, 23, 24, 25, 26, 28, 30) && is.finite(nb$Best.nc[1, col])) add(c(a[1], 100 + col - 1, a[-1]), nb$Best.nc[1, col])
  }
}
emit("factoextra", "factoextra", list(cases))
