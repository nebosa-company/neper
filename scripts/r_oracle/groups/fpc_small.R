# fpc: calinhara, neginc, cov.wml, cweight, clujaccard, cmahal, confusion.
#   "cal"/"neg": (n, p, cn, labels[n], x n by p row-major); "cwm": (n, p, r, c, wt[n], x row-major) with r, c 0-based;
#   "cw": (x, ca); "clj": (n, zbz, c1[n], c2[n]); "cm": (n, p, nmin, cmin, nc1, c1, q, at);
#   "cf": (n, k, i, j, pro[k], z n by k row-major)
suppressMessages(library(fpc))
cases <- list()
set.seed(20269901)
tol <- function(nm, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(nm, args, want, rel = 1e-9, abs = 1e-11)
for (rep in 1:40) {
  p <- sample(1:4, 1); cn <- sample(2:5, 1); n <- sample(20:80, 1)
  cl <- sample(rep(1:cn, length.out = n)); x <- matrix(rnorm(n * p) + cl, n, p)
  a <- c(n, p, cn, cl, as.vector(t(x)))
  tol("cal", a, calinhara(x, cl, cn))
  tol("neg", a, neginc(x, cl))
  wt <- runif(n); r <- sample(1:p, 1); cc <- sample(1:p, 1)
  tol("cwm", c(n, p, r - 1, cc - 1, wt, as.vector(t(x))), cov.wml(x, wt)$cov[r, cc])
}
for (rep in 1:30) { x <- abs(rnorm(1, 3, 2)); ca <- abs(rnorm(1, 3, 2)); tol("cw", c(x, ca), cweight(x, ca)) }
for (rep in 1:30) {
  n <- sample(1:30, 1); c1 <- sample(0:1, n, TRUE, prob = c(0.8, 0.2)); c2 <- sample(0:1, n, TRUE, prob = c(0.8, 0.2)); z <- rep %% 2
  tol("clj", c(n, z, c1, c2), clujaccard(c1 == 1, c2 == 1, zerobyzero = z))
}
for (rep in 1:30) {
  p <- sample(1:6, 1); nmin <- sample(2:6, 1); nc1 <- nmin + sample(2:15, 1); n <- nc1 + sample(0:20, 1)
  cmin <- runif(1, 1, 3); c1 <- cmin + runif(1, 0, 4); q <- runif(1, 0.5, 1)
  cs <- cmahal(n, p, nmin, cmin, nc1, c1, q)
  for (at in sample(seq_along(cs), 6)) tol("cm", c(n, p, nmin, cmin, nc1, c1, q, at), cs[at])
}
for (rep in 1:30) {
  n <- sample(10:40, 1); k <- sample(2:5, 1); z <- matrix(rexp(n * k), n, k); z <- z / rowSums(z); pro <- runif(k); pro <- pro / sum(pro)
  ij <- sample(1:k, 2); tol("cf", c(n, k, ij, pro, as.vector(t(z))), confusion(z, pro, ij[1], ij[2]))
}
# calinhara's edge inputs: a noise label 0 (counted in S, in no cluster), clusters of size 1, a cn below the largest label
for (rep in 1:24) {
  p <- sample(1:3, 1); cn <- sample(2:4, 1); n <- sample(15:40, 1)
  cl <- sample(rep(1:cn, length.out = n)); x <- matrix(rnorm(n * p) + cl, n, p)
  if (rep %% 3 == 1) cl[sample(n, 4)] <- 0
  if (rep %% 3 == 2) { cl[cl == cn] <- 1; cl[sample(which(cl == 1), 1)] <- cn }
  if (rep %% 3 == 0) cl[sample(n, 3)] <- 0
  cl[1:cn] <- 1:cn
  cnu <- if (rep %% 4 == 0) cn - 1 else cn
  tol("cal", c(n, p, cnu, cl, as.vector(t(x))), calinhara(x, cl, cnu))
}
emit("fpc_small", "fpc", list(cases))
