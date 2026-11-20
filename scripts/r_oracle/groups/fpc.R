# fpc: cluster.stats validity indexes from points (euclidean distances) and two clusterings.
#   args: (kind, n, k, k2, labels[n]..., alt labels[n]..., x row-major n by 2...)
#   kind: 0 average.between 1 average.within 2 max.diameter 3 min.separation 4 within.cluster.ss 5 avg.silwidth 6 g2 7 g3 8 pearsongamma 9 dunn 10 dunn2
#   11 entropy 12 wb.ratio 13 ch 14 widestgap 15 sindex 16 corrected.rand 17 vi
suppressMessages(library(fpc))
cases <- list()
add <- function(args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case("stat", args, want, rel = 1e-9, abs = 1e-10)
set.seed(20261215)
nm <- c("average.between", "average.within", "max.diameter", "min.separation", "within.cluster.ss", "avg.silwidth", "g2", "g3", "pearsongamma", "dunn", "dunn2",
        "entropy", "wb.ratio", "ch", "widestgap", "sindex", "corrected.rand", "vi")
for (rep in 1:14) {
  n <- sample(15:40, 1); k <- sample(2:5, 1); k2 <- sample(2:4, 1)
  X <- matrix(round(rnorm(n * 2) * 2 + rep(sample(0:4, n, replace = TRUE), 2) * 2, 3), n, 2)
  cl <- sample(rep(1:k, length.out = n)); cl2 <- sample(rep(1:k2, length.out = n))
  s <- cluster.stats(dist(X), cl, alt.clustering = cl2, G2 = TRUE, G3 = TRUE)
  for (kd in 0:17) {
    v <- s[[nm[kd + 1]]]
    add(c(kd, n, k, k2, cl, cl2, as.vector(t(X))), as.numeric(v))
  }
}
# cluster.varstats' varwise table of a categorised variable: "vw" args (n, ncl, cats, clustering[n], x[n], cell index = (cluster - 1) * cats + category - 1) the count
for (rep in 1:12) {
  n <- sample(30:150, 1); ncl <- sample(2:4, 1); cats <- sample(3:8, 1); cl <- sample(seq_len(ncl), n, TRUE); cl[seq_len(ncl)] <- seq_len(ncl); x <- round(rnorm(n, cl, 2), 3)
  vt <- suppressWarnings(cluster.varstats(cl, data.frame(x = x), clusterwise = FALSE, catvar = 1, catvarcats = cats))[[1]]
  tab <- matrix(0, ncl, cats); rn <- rownames(vt)[seq_len(ncl)]; cn <- as.integer(colnames(vt))
  for (i in seq_len(ncl)) for (j in seq_along(cn)) tab[as.integer(rn[i]), cn[j]] <- vt[i, j]
  for (c1 in seq_len(ncl)) for (c2 in seq_len(cats)) cases[[length(cases) + 1]] <- case("vw", c(n, ncl, cats, cl, x, (c1 - 1) * cats + c2 - 1), tab[c1, c2], rel = 0, abs = 0)
}
emit("fpc", "fpc", list(cases))
