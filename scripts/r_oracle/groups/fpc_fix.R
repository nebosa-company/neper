# fpc: fixmahal (methods fuzzy, ml and classical, cgen "fixed", with point iterations and init.group, ind.storage TRUE and FALSE), mahalconf, wfu and fpclusters.
#   "fm": (what, k, n, p, mode, startn, mnc, mer, distcut, ca, ca2, ind, ninit, ncmax, x n by p row-major, init ninit by n row-major)
#   mode 0 fuzzy, 1 ml, 2 classical. what 0: scalar k of nc, tsc, ncoll, skc, stn; what 1: the position-weighted sum of vector k of
#   0 nfound 1 er 2 imatrix 3 smatrix 4 struc 5 stfound 6 ser 7 sfpc 8 sto 9 grto 10 means 11 covs (row-major per cluster) 12 g (cluster-major) 13 fpclusters
#   "wf": (md, ca, ca2) -> wfu;  "mc": (n, p, no, startn, x n by p row-major, i) -> mahalconf(x, no + 1, startn, cov(x), "none")[i + 1]
suppressMessages(library(fpc))
cases <- list()
set.seed(20269993)
flat <- function(m) as.vector(t(unclass(as.matrix(m))))
add <- function(nm, args, want, rel = 1e-9, abs = 1e-11) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(nm, args, want, rel = rel, abs = abs)
chk <- function(v) { v <- as.numeric(unlist(v)); v[!is.finite(v)] <- 0; sum(seq_along(v) * v) }
for (rep in 1:20) {
  md <- runif(1, 0, 20); ca <- runif(1, 2, 8); ca2 <- ca + runif(1, 0.5, 6)
  add("wf", c(md, ca, ca2), wfu(md, ca, ca2), 1e-12, 1e-14)
}
for (rep in 1:6) {
  p <- sample(2:3, 1); n <- sample(25:40, 1); x <- round(matrix(rnorm(n * p), n, p) + outer(sample(0:1, n, TRUE), rep(3, p)), 4); startn <- 18 + p; startn <- min(startn, n)
  no <- sample(n, 1); gv <- mahalconf(x, no, startn, cov(x), "none")
  for (i in sample(n, 6)) add("mc", c(n, p, no - 1, startn, flat(x), i - 1), as.numeric(gv[i]), 0, 0)
}
blobs <- function(n, p) {
  k <- 2; m <- c(n %/% 2, n - n %/% 2); ctr <- matrix(c(0, 5, 0, 5, 0, 5)[1:(k * p)], k, p) + matrix(runif(k * p), k, p)
  round(do.call(rbind, lapply(seq_len(k), function(g) matrix(rnorm(m[g] * p, 0, 0.8), m[g], p) + rep(ctr[g, ], each = m[g]))), 4)
}
for (rep in 1:9) {
  p <- c(2, 2, 3)[rep %% 3 + 1]; n <- sample(24:34, 1); x <- blobs(n, p)
  mode <- rep %% 3; meth <- c("fuzzy", "ml", "classical")[mode + 1]
  startn <- min(18 + p, n); mnc <- floor(startn / 2); mer <- 0.1; distcut <- 0.85
  ca <- if (mode == 0) qchisq(0.95, p) else qchisq(0.99, p); ca2 <- if (mode == 0) qchisq(0.995, p) else 0
  ind <- rep %% 2 == 0
  ng <- 2; ninit <- if (rep %% 4 == 1) 2 else 0
  init <- lapply(seq_len(ninit), function(i) { g <- rep(FALSE, n); g[sample(n, p + 3)] <- TRUE; g })
  r <- suppressWarnings(fixmahal(x, method = meth, ca = ca, ca2 = if (mode == 0) ca2 else NA, startn = startn, mnc = mnc, mer = mer, distcut = distcut, ind.storage = ind, init.group = init, countmode = 1e9))
  ncmax <- r$nc + 3
  hd <- function(w, k) c(w, k, n, p, mode, startn, mnc, mer, distcut, ca, ca2, ind, ninit, ncmax, flat(x), if (ninit > 0) unlist(lapply(init, as.numeric)))
  for (k in 0:4) add("fm", hd(0, k), c(r$nc, r$tsc, r$ncoll, r$skc, r$stn)[k + 1], 0, 0)
  vecs <- list(r$nfound, r$er, r$imatrix, r$smatrix, r$struc, r$stfound, r$ser, r$sfpc, r$sto, if (ninit > 0) r$grto else 0, r$means, lapply(r$covs, function(m) flat(m)), if (ind) r$g else 0)
  for (k in 0:12) { if ((k == 12 || k == 13) && !ind) next; add("fm", hd(1, k), chk(vecs[[k + 1]]), 1e-8, 1e-10) }
  if (ind && r$stn > 0) add("fm", hd(1, 13), chk(lapply(fpclusters(r), as.numeric)), 1e-8, 1e-10)
  if (r$stn > 0) add("fm", hd(1, 14), chk(simmatrix(r)), 1e-8, 1e-10)
}
emit("fpc_fix", "fpc", list(cases))
