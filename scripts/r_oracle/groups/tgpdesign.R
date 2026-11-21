# tgpdesign: tgp::dopt.gp, the sequential D-optimal design, and tgp.design on a fit with no tree (one partition),
# under set.seed. Data: X = matrix(runif(n m), n, m) from the data seed, then Xcand = matrix(runif(ncand m), ncand, m).
# fn "dopt": args data seed, seed, nn, n, m, ncand, iter, k: the k-th chosen candidate index fi (n = 0 means X = NULL).
# fn "design": tgp.design(nn, Xcand, fit) with the default iter = 5000, the chosen candidate index of the k-th row.
library(tgp)

make <- function(ds, n, m, ncand) {
  set.seed(ds)
  X <- if (n > 0) matrix(runif(n * m), n, m) else NULL
  Xc <- matrix(runif(ncand * m), ncand, m)
  list(X = X, Xc = Xc)
}

configs <- list(
  list(ds = 31, seed = 2, nn = 5, n = 10, m = 2, ncand = 30, iter = 300),
  list(ds = 32, seed = 17, nn = 4, n = 0, m = 3, ncand = 20, iter = 500),
  list(ds = 33, seed = 99, nn = 6, n = 15, m = 1, ncand = 25, iter = 200),
  list(ds = 34, seed = 5, nn = 3, n = 8, m = 4, ncand = 12, iter = 1000),
  list(ds = 35, seed = 123, nn = 8, n = 20, m = 2, ncand = 8, iter = 100)
)

cases <- list()
for (cf in configs) {
  dat <- make(cf$ds, cf$n, cf$m, cf$ncand)
  set.seed(cf$seed)
  fi <- dopt.gp(cf$nn, dat$X, dat$Xc, iter = cf$iter)$fi
  for (k in seq_along(fi))
    cases[[length(cases) + 1]] <- list(case("dopt", c(cf$ds, cf$seed, cf$nn, cf$n, cf$m, cf$ncand, cf$iter, k - 1),
                                            fi[k], rel = 0, abs = 0))
}

for (cf in configs[c(1, 3, 4)]) {
  dat <- make(cf$ds, cf$n, cf$m, cf$ncand)
  Z <- sin(4 * dat$X[, 1]) + 0.1 * rnorm(cf$n)
  set.seed(cf$seed + 1)
  fit <- blm(dat$X, Z, BTE = c(4, 12, 2), verb = 0)
  set.seed(cf$seed)
  des <- suppressMessages(tgp.design(cf$nn, dat$Xc, fit))
  fi <- vapply(seq_len(nrow(des)), function(i) which(apply(dat$Xc, 1, function(r) all(r == des[i, ])))[1], 1)
  for (k in seq_along(fi))
    cases[[length(cases) + 1]] <- list(case("design", c(cf$ds, cf$seed, cf$nn, cf$n, cf$m, cf$ncand, 5000, k - 1),
                                            fi[k], rel = 0, abs = 0))
}

emit("tgpdesign", "tgp", cases)
