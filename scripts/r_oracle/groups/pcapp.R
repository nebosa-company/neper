# pcaPP: cor.fk, l1median_HoCr, l1median_VaZh and the default l1median (nlm). hocr and nlm are compared to the tolerance: HoCr stops on a
# strict decrease of a sum of 100 square roots, which the last bit of pow decides; code and iterations are compared for vazh only.
#   corfk: (n, x[n], y[n])
#   hocr, vazh, nlm: (n, p, maxit, tol, zero.tol, X[n*p column-major], m0[p], what) what 0..p-1 par, p value, p+1 code, p+2 iterations
suppressMessages(library(pcaPP))
library(stats)
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261120)
for (rep in 1:60) {
  n <- sample(c(5, 8, 20, 50, 200), 1)
  x <- if (rep %% 3 == 0) round(rnorm(n) * 2) else rnorm(n)
  y <- if (rep %% 4 == 0) round(x + rnorm(n)) else x * 0.5 + rnorm(n)
  add("corfk", c(n, x, y), cor.fk(x, y))
}
for (rep in 1:40) {
  p <- sample(1:5, 1); n <- sample(c(10, 30, 60, 120), 1)
  X <- matrix(if (rep %% 2 == 0) rnorm(n * p) else rt(n * p, 3), n, p)
  m0 <- apply(X, 2, median)
  hc <- l1median_HoCr(X, m.init = m0)
  vz <- l1median_VaZh(X, m.init = m0)
  nl <- tryCatch(l1median_NLM(X, m.init = m0), error = function(e) NULL)
  a <- c(n, p, 200, 1e-8, 1e-15, X, m0)
  for (j in 1:p) { add("hocr", c(a, j - 1), hc$par[j], rel = 1e-6, abs = 1e-7); add("vazh", c(a, j - 1), vz$par[j]) }
  add("hocr", c(a, p), hc$value); add("vazh", c(a, p), vz$value)
  add("vazh", c(a, p + 1), vz$code)
  add("vazh", c(a, p + 2), vz$iterations)
  if (!is.null(nl)) {
    for (j in 1:p) add("nlm", c(a, j - 1), nl$par[j], rel = 1e-5, abs = 1e-6)
    add("nlm", c(a, p), nl$value, rel = 1e-7, abs = 1e-8)
  }
}
#   qn: (n, x[n], what 0) fn "qn"; pj: (n, p, k, method, update, maxit, maxhalf, zero.tol, X[n*p], m[p], what) what 0..k-1 sdev, then loadings (p*k), then scores (n*k)
for (v in c(0, 5, 6, 7, 10, 11, 25, 60)) if (v) {
  x <- if (v %% 2) rnorm(v) else round(rnorm(v), 1)
  add("qn", c(v, x), qn(x))
}
for (rep in 1:30) {
  p <- sample(2:4, 1); k <- sample(1:min(p, 3), 1); n <- sample(c(12, 25, 40), 1)
  X <- matrix(rnorm(n * p), n, p) %*% matrix(rnorm(p * p), p, p)
  if (rep %% 3 == 0) X[1:2, ] <- X[1:2, ] * 8
  m <- apply(X, 2, median)
  for (me in 0:2) for (up in c(TRUE, FALSE)) {
    r <- tryCatch(suppressWarnings(PCAproj(X, k = k, method = c("sd", "mad", "qn")[me + 1], CalcMethod = "eachobs", update = up, center = m, scale = NULL)), error = function(e) NULL)
    if (is.null(r)) next
    a <- c(n, p, k, me, as.numeric(up), 5, 5, 1e-16, X, m)
    for (j in 1:k) add("pj", c(a, j - 1), r$sdev[j], 1e-8, 1e-10)
    L <- unclass(r$loadings)
    for (j in 1:(p * k)) add("pj", c(a, k + j - 1), L[j], 1e-8, 1e-10)
    S <- r$scores
    for (j in 1:(n * k)) add("pj", c(a, k + p * k + j - 1), S[j], 1e-8, 1e-10)
  }
}
#   pg: (n, p, k, method, maxiter, splitcircle, zero.tol, X[n*p], m[p], what) what 0..k-1 sdev, k..k+p*k-1 loadings, then obj (k)
for (rep in 1:30) {
  p <- sample(2:4, 1); k <- sample(1:p, 1); n <- sample(c(15, 30, 50), 1)
  X <- matrix(rnorm(n * p), n, p) %*% matrix(rnorm(p * p), p, p)
  if (rep %% 3 == 0) X[1:2, ] <- X[1:2, ] * 8
  m <- apply(X, 2, median)
  for (me in 0:2) {
    mx <- sample(c(3, 10), 1); sc <- sample(c(10, 25), 1)
    r <- tryCatch(suppressWarnings(PCAgrid(X, k = k, method = c("sd", "mad", "qn")[me + 1], maxiter = mx, splitcircle = sc, center = m, scale = NULL)), error = function(e) NULL)
    if (is.null(r)) next
    a <- c(n, p, k, me, mx, sc, 1e-16, X, m)
    for (j in 1:k) add("pg", c(a, j - 1), r$sdev[j], 1e-8, 1e-10)
    L <- unclass(r$loadings)
    for (j in 1:(p * k)) add("pg", c(a, k + j - 1), L[j], 1e-7, 1e-9)
    for (j in 1:k) add("pg", c(a, k + p * k + j - 1), r$obj[j], 1e-8, 1e-10)
  }
}
for (rep in 1:20) {  # n < p: the SVD reduction
  n <- sample(4:7, 1); p <- n + sample(1:4, 1); k <- sample(1:min(n - 1, 3), 1)
  X <- matrix(rnorm(n * p), n, p)
  m <- rep(0, p)  # R centres the reduced data, and a length-p centre does not fit it: pass none
  for (me in 0:2) {
    r <- tryCatch(suppressWarnings(PCAgrid(X, k = k, method = c("sd", "mad", "qn")[me + 1], maxiter = 5, splitcircle = 25, center = NULL, scale = NULL)), error = function(e) NULL)
    if (is.null(r)) next
    a <- c(n, p, k, me, 5, 25, 1e-16, X, m)
    for (j in 1:k) add("pg", c(a, j - 1), r$sdev[j], 1e-7, 1e-9)
    L <- unclass(r$loadings)
    for (j in 1:(p * k)) add("pg", c(a, k + j - 1), L[j], 1e-6, 1e-8)
    for (j in 1:k) add("pg", c(a, k + p * k + j - 1), r$obj[j], 1e-7, 1e-9)
  }
}
#   sg: (n, p, k, method, maxiter, splitcircle, zero.tol, norm.q, norm.s, lambda[k], X[n*p], m[p], what) as pg
for (rep in 1:30) {
  p <- sample(2:4, 1); k <- sample(1:p, 1); n <- sample(c(15, 30, 50), 1)
  X <- matrix(rnorm(n * p), n, p) %*% matrix(rnorm(p * p), p, p)
  m <- apply(X, 2, median)
  for (me in 0:2) {
    mx <- sample(c(3, 10), 1); sc <- sample(c(10, 25), 1)
    lam <- round(runif(k, 0, 2), 2); if (rep %% 4 == 0) lam[1] <- 0
    nq <- sample(c(1, 1, 0.7, 2), 1); ns <- sample(c(1, 1, 0.8, 2), 1)
    r <- tryCatch(suppressWarnings(sPCAgrid(X, k = k, method = c("sd", "mad", "qn")[me + 1], lambda = lam, maxiter = mx, splitcircle = sc, center = m, scale = NULL, norm.q = nq, norm.s = ns)), error = function(e) NULL)
    if (is.null(r)) next
    a <- c(n, p, k, me, mx, sc, 1e-16, nq, ns, lam, X, m)
    for (j in 1:k) add("sg", c(a, j - 1), r$sdev[j], 1e-8, 1e-10)
    L <- unclass(r$loadings)
    for (j in 1:(p * k)) add("sg", c(a, k + j - 1), L[j], 1e-7, 1e-9)
    for (j in 1:k) add("sg", c(a, k + p * k + j - 1), r$obj[j], 1e-8, 1e-10)
  }
}
emit("pcapp", "pcaPP", list(cases))
