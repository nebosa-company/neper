# fpc: clusexpect, itnumber, minsize, distancefactor, randcmatrix, randconf, mahalanofix, mahalanofuz, localshape (mscatter "cov"), cat2bin, discrete.recode.
#   "ce": (n, p, cn, ir); "it": (n, p, cn, mtf, prob, maxir); "ms": (n, p, ir, mtf, prob)
#   "df": (cat, n, ordinal, normfactor, qfactor, nsizes, sizes...)
#   "rc": (seed, n, cln, p, row, col) -> m[row, col] (0-based) ; "rs": (seed, n, cln, p) -> sum((i + 1) * (j + 1) * m[i, j])
#   "rf": (seed, n, p, i) -> flag i (0-based)
#   "mf": (fuzzy, what, idx, n, p, gv[n], x n by p row-major); what 0 md[idx], 1 mg[idx], 2 covg[idx] row-major, 3 covinv[idx] row-major, 4 sum((i + 1) * md[i])
#   "ls": (proportion, covstandard 0 trace 1 det 2 none, idx, n, p, x); the value is lcov[idx] row-major
#   "rec": (what, idx, n, v[n]); what 0 ppdim, 1 recode[idx], 2 cat2bin indicator column idx summed with weights (i + 1)
suppressMessages(library(fpc))
cases <- list()
set.seed(20269981)
flat <- function(m) as.vector(t(unclass(m)))
tol <- function(nm, args, want, rel = 1e-9, abs = 1e-11) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(nm, args, want, rel = rel, abs = abs)
for (rep in 1:40) {
  p <- sample(1:5, 1); n <- sample(30:400, 1); cn <- sample((p + 2):(n - 1), 1); ir <- sample(1:200, 1)
  tol("ce", c(n, p, cn, ir), clusexpect(n, p, cn, ir), 1e-12)
}
for (rep in 1:30) {
  p <- sample(1:4, 1); n <- sample(40:300, 1); cn <- sample((p + 2):(n - 1), 1); mtf <- sample(1:5, 1); prob <- c(0.5, 0.9, 0.95)[rep %% 3 + 1]
  tol("it", c(n, p, cn, mtf, prob, 20000), suppressWarnings(itnumber(n, p, cn, mtf, prob)), 0, 0)
}
for (rep in 1:30) {
  p <- sample(1:4, 1); n <- sample(40:300, 1); ir <- sample(c(5, 20, 100, 1000), 1); mtf <- sample(1:5, 1); prob <- c(0.5, 0.9, 0.95)[rep %% 3 + 1]
  tol("ms", c(n, p, ir, mtf, prob), suppressWarnings(minsize(n, p, ir, mtf, prob)), 0, 0)
}
for (rep in 1:40) {
  cat <- sample(2:6, 1); ord <- rep %% 2; ty <- c("categorical", "ordinal")[ord + 1]; nf <- c(2, 1, 3)[rep %% 3 + 1]
  if (rep %% 4 < 2) {
    n <- sample(20:200, 1)
    tol("df", c(cat, n, ord, nf, if (ord == 1) 1 / (1 + 1 / (cat - 1)) else 1 / 2, 0), distancefactor(cat, n, type = ty, normfactor = nf), 1e-12)
  } else {
    cs <- sample(3:40, cat, TRUE)
    qf <- runif(1, 0.3, 0.9)
    tol("df", c(cat, 0, ord, nf, qf, cat, cs), distancefactor(cat, catsizes = cs, type = ty, normfactor = nf, qfactor = qf), 1e-12)
  }
}
for (rep in 1:20) {
  n <- sample(30:120, 1); cln <- sample(2:5, 1); p <- sample(1:4, 1); seed <- sample(1:100000, 1)
  set.seed(seed); m <- randcmatrix(n, cln, p)
  tol("rs", c(seed, n, cln, p), sum(outer(seq_len(n), seq_len(cln), function(i, j) i * j) * m), 0, 0)
  for (k in 1:3) { i <- sample(n, 1); j <- sample(cln, 1); tol("rc", c(seed, n, cln, p, i - 1, j - 1), m[i, j], 0, 0) }
}
for (rep in 1:20) {
  n <- sample(10:60, 1); p <- sample(2:n, 1); seed <- sample(1:100000, 1)
  set.seed(seed); g <- randconf(n, p)
  for (i in sample(n, 5)) tol("rf", c(seed, n, p, i - 1), as.numeric(g[i]), 0, 0)
}
for (rep in 1:10) {
  p <- sample(1:4, 1); n <- sample(20:40, 1); fz <- rep %% 2
  x <- round(matrix(rnorm(n * p), n, p) %*% matrix(runif(p * p, -1, 1), p, p) + 2, 4)
  gv <- if (fz == 1) sample(0:1, n, TRUE) else sample(c(TRUE, FALSE), n, TRUE, prob = c(0.7, 0.3))
  gv[1:(p + 3)] <- 1
  r <- if (fz == 1) mahalanofuz(x, gv = gv) else mahalanofix(x, gv = gv)
  g <- as.numeric(gv)
  hdr <- function(w, i) c(fz, w, i, n, p, g, flat(x))
  tol("mf", hdr(4, 0), sum(seq_len(n) * r$md), 1e-9)
  for (i in sample(n, 3)) tol("mf", hdr(0, i - 1), r$md[i], 1e-9)
  for (j in 1:p) tol("mf", hdr(1, j - 1), r$mg[j], 1e-9)
  for (rr in 1:p) for (cc in 1:p) { tol("mf", hdr(2, (rr - 1) * p + cc - 1), r$covg[rr, cc], 1e-9); tol("mf", hdr(3, (rr - 1) * p + cc - 1), r$covinv[rr, cc], 1e-9) }
}
for (rep in 1:9) {
  p <- sample(2:3, 1); n <- sample(30:45, 1); st <- c("trace", "det", "none")[rep %% 3 + 1]; pr <- c(0.1, 0.2, 0.3)[rep %% 3 + 1]
  x <- round(matrix(rnorm(n * p), n, p) %*% matrix(runif(p * p, -1, 1), p, p), 4)
  r <- localshape(x, proportion = pr, mscatter = "cov", covstandard = st)
  for (rr in 1:p) for (cc in 1:p) tol("ls", c(pr, rep %% 3, (rr - 1) * p + cc - 1, n, p, flat(x)), r[rr, cc], 1e-9, 1e-12)
}
for (rep in 1:20) {
  n <- sample(10:60, 1); ncat <- sample(2:6, 1); v <- sample(c(sort(sample(-5:20, ncat))), n, TRUE)
  rr <- discrete.recode(matrix(v, n, 1), xvarsorted = TRUE, continuous = 0, discrete = 1)
  tol("rec", c(0, 0, n, v), rr$ppdim[1], 0, 0)
  for (i in sample(n, 4)) tol("rec", c(1, i - 1, n, v), rr$data[i, 1], 0, 0)
  b <- cat2bin(matrix(v, n, 1), categorical = 1)$data
  for (j in seq_len(ncol(b))) tol("rec", c(2, j - 1, n, v), sum(seq_len(n) * b[, j]), 0, 0)
}
emit("fpc_extra", "fpc", list(cases))
