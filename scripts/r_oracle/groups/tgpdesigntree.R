# tgpdesigntree: tgp.design(howmany, Xcand, fit) on a fit with a tree (btlm, md 0; btgp, md 1; the data have a jump in
# x1 so the best tree splits), under set.seed. Data: X, then the noise, then XX, then Xcand = matrix(runif(ncand d)),
# all from the data seed. fn "design": args data seed, seed, design seed, n, d, nn, ncand, howmany, B, T, E, md, k: the
# 1-based Xcand row of the k-th design row; fn "ndesign" the number of design rows (k = 0).
library(tgp)

configs <- list(
  list(ds = 31, seed = 4, dseed = 3, n = 70, d = 2, nn = 4, ncand = 40, howmany = 8, B = 200, T = 800, E = 2, md = 0),
  list(ds = 32, seed = 9, dseed = 11, n = 60, d = 1, nn = 4, ncand = 30, howmany = 6, B = 150, T = 600, E = 2, md = 0),
  list(ds = 34, seed = 6, dseed = 5, n = 70, d = 2, nn = 4, ncand = 50, howmany = 10, B = 200, T = 800, E = 2, md = 0),
  list(ds = 53, seed = 7, dseed = 2, n = 80, d = 2, nn = 4, ncand = 40, howmany = 7, B = 100, T = 500, E = 2, md = 1),
  list(ds = 54, seed = 7, dseed = 8, n = 60, d = 1, nn = 4, ncand = 30, howmany = 5, B = 100, T = 500, E = 2, md = 1)
)

cases <- list()
for (cf in configs) {
  set.seed(cf$ds)
  d <- cf$d; n <- cf$n
  X <- matrix(runif(n * d), n, d)
  x2 <- if (d > 1) X[, 2] else rep(0, n)
  jump <- if (cf$md == 0) 0 else 3
  z <- if (cf$md == 0) ifelse(X[, 1] < 0.4, 1 + 2 * x2, -1 + sin(8 * X[, 1]) + 0.5 * x2)
       else ifelse(X[, 1] < 0.45, 1 + 0.5 * x2, 1 + jump + sin(10 * X[, 1]) + 0.5 * x2)
  noise <- if (cf$md == 0) 0.1 else 0.02
  Z <- z + noise * rnorm(n)
  XX <- matrix(runif(cf$nn * d), cf$nn, d)
  Xc <- matrix(runif(cf$ncand * d), cf$ncand, d)
  set.seed(cf$seed)
  if (cf$md == 0) fit <- btlm(X, Z, XX, BTE = c(cf$B, cf$T, cf$E), verb = 0)
  else fit <- btgp(X, Z, XX, BTE = c(cf$B, cf$T, cf$E), verb = 0)
  set.seed(cf$dseed)
  des <- suppressMessages(tgp.design(cf$howmany, Xc, fit))
  fi <- vapply(seq_len(nrow(des)), function(i) which(apply(Xc, 1, function(r) all(r == des[i, ])))[1], 1)
  key <- c(cf$ds, cf$seed, cf$dseed, cf$n, cf$d, cf$nn, cf$ncand, cf$howmany, cf$B, cf$T, cf$E, cf$md)
  cases[[length(cases) + 1]] <- list(case("ndesign", c(key, 0), nrow(des), rel = 0, abs = 0))
  for (k in seq_along(fi))
    cases[[length(cases) + 1]] <- list(case("design", c(key, k - 1), fi[k], rel = 0, abs = 0))
}

emit("tgpdesigntree", "tgp", cases)
