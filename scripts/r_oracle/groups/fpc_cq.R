# fpc::cqcluster.stats on the Euclidean distances of a data matrix.
#   "cq": (what, kind, n, p, cn, noise, flags, stdmode, sepall, sepwn, sepprob, dq, nnk, nndist, k2, cl[n], alt[n] when k2 > 0, x n by p row-major)
#   kind 0: scalar number `what` of the out layout in fpc_cq.e; kind 1: the position-weighted sum of vector `what` (NA as 0):
#   0 cvnndc 1 npenalty 2 dpenalty 3 pamcentroids 4 withindensp 5 densoc 6 percwdens 7 percdensoc 8 psep 9 svec 10 pclosetomode 11 distto 12 pdistto
#   flags: 1 silhouette 2 G2 4 G3 8 wgap 16 averagegap
suppressMessages(library(fpc))
cases <- list()
set.seed(20269987)
flat <- function(m) as.vector(t(unclass(m)))
snames <- c("n", "cluster.number", "min.cluster.size", "noisen", "avebetween", "avewithin", "maxdiameter", "minsep", "withinss", "asw", "g2", "g3", "pearsongamma", "dunn", "dunn2",
  "entropy", "wb.ratio", "ch", "widestgap", "corrected.rand", "vi", "sindex", "stan", "mnnd", "pamc", "dindex", "denscut", "highdgap", "parsimony", "cvnnd", "n.between", "n.within")
vnames <- c("cvnndc", "npenalty", "dpenalty", "pamcentroids", "withindensp", "densoc", "percwdens", "percdensoc", "psep", "svec", "pclosetomode", "distto", "pdistto")
chk <- function(v) { v <- as.numeric(unlist(v)); v[!is.finite(v)] <- 0; sum(seq_along(v) * v) }
for (rep in 1:14) {
  p <- sample(2:3, 1); cn <- sample(2:4, 1); n <- sample(30:45, 1)
  noise <- rep %% 3 == 0
  cl <- sample(rep(1:cn, length.out = n)); cl[1:cn] <- 1:cn
  if (noise) { cl[sample(n, 4)] <- cn; cl[1:cn] <- 1:cn }
  x <- round(matrix(rnorm(n * p), n, p) + outer(cl, seq_len(p)) * 0.9, 4)
  k2 <- if (rep %% 2 == 0) sample(2:3, 1) else 0
  alt <- if (k2 > 0) { a <- sample(rep(1:k2, length.out = n)); a[1:k2] <- 1:k2; a } else integer(0)
  flags <- 1 + 2 * (rep %% 2) + 4 * (rep %% 3 == 1) + 8 + 16 * (rep %% 4 < 2)
  stdmode <- c(0, 0, 1, 2, 3)[rep %% 5 + 1]
  sepall <- TRUE; sepwn <- rep %% 2 == 1; sepprob <- c(0.1, 0.25)[rep %% 2 + 1]; dq <- c(0.1, 0.2)[rep %% 2 + 1]
  nnk <- c(2, 1, 3)[rep %% 3 + 1]
  nndist <- rep %% 5 != 4
  d <- dist(x)
  r <- suppressWarnings(cqcluster.stats(d, cl, alt.clustering = if (k2 > 0) alt else NULL, noisecluster = noise, silhouette = bitwAnd(flags, 1) > 0, G2 = bitwAnd(flags, 2) > 0,
    G3 = bitwAnd(flags, 4) > 0, wgap = TRUE, sepindex = TRUE, sepprob = sepprob, sepwithnoise = sepwn, averagegap = bitwAnd(flags, 16) > 0, pamcrit = TRUE, dquantile = dq,
    nndist = nndist, nnk = nnk, standardisation = c("max", "ave", "q90", "none")[stdmode + 1], sepall = sepall))
  hdr <- function(w, k) c(w, k, n, p, cn, noise, flags, stdmode, sepall, sepwn, sepprob, dq, nnk, nndist, k2, cl, alt, flat(x))
  for (i in seq_along(snames)) {
    v <- r[[snames[i]]]
    if (!is.null(v) && length(v) == 1 && is.finite(v)) cases[[length(cases) + 1]] <- case("cq", hdr(i - 1, 0), v, rel = 1e-9, abs = 1e-11)
  }
  for (i in seq_along(vnames)) {
    v <- r[[vnames[i]]]
    if (!is.null(v)) cases[[length(cases) + 1]] <- case("cq", hdr(i - 1, 1), chk(v), rel = 1e-8, abs = 1e-10)
  }
}
emit("fpc_cq", "fpc", list(cases))
