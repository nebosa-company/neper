# fpc: cluster.stats validity indexes from points (euclidean distances) and two clusterings.
#   args: (kind, n, k, k2, labels[n]..., alt labels[n]..., x row-major n by 2...)
#   kind: 0 average.between 1 average.within 2 max.diameter 3 min.separation 4 within.cluster.ss 5 avg.silwidth 6 g2 7 g3 8 pearsongamma 9 dunn 10 dunn2
#   11 entropy 12 wb.ratio 13 ch 14 widestgap 15 sindex 16 corrected.rand 17 vi
suppressMessages(library(fpc))
cases <- list()
add <- function(args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case("stat", args, want, rel = 1e-8, abs = 1e-10)
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
emit("fpc", "fpc", list(cases))
