# kernlab ksvm bound-constrained and multi-class solvers: C-bsvc, eps-bsvr (Solver_B with TRON, Solver_B_linear for vanilladot), kbb-svc (Solver_MB), spoc-svc (Solver_SPOC).
#   two-class / regression args: (n, p, ktype, svm, C, pe, gamma, degree, coef0, y[n], x[n*p] row-major), svm 5 = C-bsvc (y of either sign, class 1 first), 6 = eps-bsvr
#     fn "alpha" (position-weighted signed coefficients), "b", "obj", "dec" (position-weighted decision values on the training points)
#   multi-class args: (n, p, K, ktype, svm, C, gamma, degree, coef0, nt, cls[n] 0-based in ksvm's sorted order, x[n*p] sorted, xt[nt*p]), svm 5 = C-bsvc voting, 7 = spoc-svc, 8 = kbb-svc
#     fn "alpha" (position-weighted coefficients: pairwise signed for 5, the n by K matrix for 7, the n by K - 1 matrix for 8), "obj" (sum for 5), "resp" (position-weighted predicted classes, 1-based), "b" (kbb, 5)
#   kernlab's dprecond keeps a static lambda that doubles whenever the shifted Cholesky also fails, so the fits depend on every earlier fit of the session: the cases are
#   in fit order and the first case of each model is its "alpha", which is where the fixture lets the state advance.
#   spoc-svc and kbb-svc report no objective (uninitialised memory in kernlab) and kernlab overwrites alpha element n (spoc row-major, kbb column-major) with it, so that cell is zeroed.
suppressMessages(library(kernlab))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-11) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
ws <- function(v) sum(as.vector(v) * seq_along(v))
mk <- function(kt, sg, dg, off) switch(as.character(kt), "0" = vanilladot(), "1" = polydot(dg, sg, off), "2" = rbfdot(sg), "3" = tanhdot(sg * 0.3, off - 0.5),
                                    "5" = laplacedot(sg), "7" = anovadot(sg, dg), "8" = splinedot(), "6" = besseldot(sg, 1, 2))
gm <- function(kt, sg) switch(as.character(kt), "0" = 0, "1" = sg, "2" = sg, "3" = sg * 0.3, "5" = sg, "7" = sg, "8" = 0, "6" = sg)
cf <- function(kt, off) switch(as.character(kt), "1" = off, "3" = off - 0.5, "6" = 2, 0)
dgr <- function(kt, dg) if (kt %in% c(1, 7)) dg else if (kt == 6) 1 else 1
set.seed(20261501)
kinds <- c(0, 1, 2, 3, 5, 7, 8)
for (rep in 1:56) {
  kt <- kinds[(rep - 1) %% 7 + 1]
  n <- sample(20:40, 1); p <- sample(2:4, 1); n1 <- n %/% 2
  C <- runif(1, 0.5, 8); sg <- runif(1, 0.1, 1.2); dg <- sample(2:3, 1); off <- runif(1, 0, 1)
  x <- rbind(matrix(rnorm(n1 * p, -0.6, 0.8), n1), matrix(rnorm((n - n1) * p, 0.6, 0.8), n - n1))
  if (kt == 8) x <- x / 3
  yf <- factor(rep(1:2, c(n1, n - n1))); yd <- ifelse(as.integer(yf) == 1, -1, 1)
  kn <- mk(kt, sg, dg, off)
  m <- ksvm(x, yf, type = "C-bsvc", kernel = kn, C = C, scaled = FALSE)
  full <- numeric(n); full[alphaindex(m)[[1]]] <- coef(m)[[1]]
  K <- as.matrix(kernelMatrix(kn, x)); dec <- as.vector(K %*% full - b(m))
  a <- c(n, p, kt, 5, C, 0.1, gm(kt, sg), dgr(kt, dg), cf(kt, off), yd, as.vector(t(x)))
  add("alpha", a, ws(full)); add("b", a, b(m)); add("obj", a, obj(m)); add("dec", a, ws(dec), rel = 1e-8)
}
kinds <- c(1, 2, 3, 5, 7, 8)
for (rep in 1:48) {
  kt <- kinds[(rep - 1) %% 6 + 1]
  n <- sample(20:40, 1); p <- sample(2:3, 1)
  C <- runif(1, 0.5, 8); pe <- runif(1, 0.05, 0.3); sg <- runif(1, 0.1, 1.2); dg <- sample(2:3, 1); off <- runif(1, 0, 1)
  x <- matrix(rnorm(n * p), n); if (kt == 8) x <- x / 3
  y <- sin(x[, 1]) + 0.1 * rnorm(n)
  kn <- mk(kt, sg, dg, off)
  m <- ksvm(x, y, type = "eps-bsvr", kernel = kn, C = C, epsilon = pe, scaled = FALSE)
  full <- numeric(n); full[alphaindex(m)] <- coef(m)
  K <- as.matrix(kernelMatrix(kn, x)); dec <- as.vector(K %*% full - b(m))
  a <- c(n, p, kt, 6, C, pe, gm(kt, sg), dgr(kt, dg), cf(kt, off), y, as.vector(t(x)))
  add("alpha", a, ws(full)); add("b", a, b(m)); add("obj", a, obj(m)); add("dec", a, ws(dec), rel = 1e-8)
}
kinds <- c(2, 1, 0, 3, 5, 7, 8)
for (rep in 1:63) {
  kt <- kinds[(rep - 1) %% 7 + 1]; sv <- c(7, 8, 5)[(rep - 1) %/% 7 %% 3 + 1]
  K <- c(3, 4)[(rep %/% 3) %% 2 + 1]; p <- sample(2:4, 1); per <- sample(7:12, 1)
  n <- K * per
  C <- runif(1, 0.5, 8); sg <- runif(1, 0.1, 1.0); dg <- sample(2:3, 1); off <- runif(1, 0, 1)
  ctr <- matrix(rnorm(K * p, 0, 1.2), K)
  cls0 <- rep(1:K, per)[sample(n)]
  x0 <- ctr[cls0, , drop = FALSE] + matrix(rnorm(n * p, 0, 1), n)
  if (kt == 8) x0 <- x0 / 3
  xt <- matrix(rnorm(8 * p, 0, 1.5), 8); if (kt == 8) xt <- xt / 3
  kn <- mk(kt, sg, dg, off)
  yfac <- factor(cls0)
  type <- c("5" = "C-bsvc", "7" = "spoc-svc", "8" = "kbb-svc")[as.character(sv)]
  m <- ksvm(x0, yfac, type = type, kernel = kn, C = C, scaled = FALSE)
  # one-against-one vanilladot C-bsvc, four classes of 12: kernlab's sixth pair stops at a different point (objective -22.04 where this port reaches -23.65, the other five pairs agree
  # to 1e-15). Not rounding (the port's answer is stable under 1e-16 changes of the data); the outcome moves with whether the repeated-working-set test fires at the first check of a
# restarted solve, which reads kernlab's uninitialised old_working_set, and no layout tried reproduces kernlab's value. The fit is left out of the comparison, and listed as open.
  if (sv == 5 && kt == 0 && K == 4 && n == 48) next
  ix <- if (sv == 5) order(cls0, method = "radix") else sort(cls0, method = "quick", index.return = TRUE)$ix
  x <- x0[ix, , drop = FALSE]; cls <- cls0[ix]
  a <- c(n, p, K, kt, sv, C, gm(kt, sg), dgr(kt, dg), cf(kt, off), nrow(xt), cls - 1, as.vector(t(x)), as.vector(t(xt)))
  pr <- as.integer(predict(m, xt))
  if (sv == 5) {
    full <- unlist(lapply(seq_along(alphaindex(m)), function(q) { f <- numeric(n); f[match(alphaindex(m)[[q]], ix)] <- coef(m)[[q]]; f }))
    add("alpha", a, ws(full)); add("b", a, ws(b(m))); add("obj", a, sum(obj(m)))
  } else {
    # kernlab writes the objective, which spoc-svc and kbb-svc never set (uninitialised memory), over alpha element n of the raw layout: spoc by row, kbb by column
    raw <- alpha(m)[ix, , drop = FALSE]
    gcell <- if (sv == 7) raw[n %/% K + 1, n %% K + 1] else raw[1, 2]
    garbage <- abs(gcell) > 1e-200
    if (sv == 7) raw[n %/% K + 1, n %% K + 1] <- 0 else raw[1, 2] <- 0
    add("alpha", a, ws(t(raw)))
    if (sv == 8) add("b", a, ws(-colSums(raw)))
  }
  if (!(sv %in% c(7, 8)) || !garbage) add("resp", a, ws(pr))
}
# Bessel kernel (kind 6): besseldot(sigma, order, degree), carried as gamma = sigma, degree = order, coef0 = kernlab's degree
for (rep in 1:12) {
  sv <- if (rep <= 6) 5 else 6
  n <- sample(20:36, 1); p <- sample(2:3, 1); n1 <- n %/% 2
  C <- runif(1, 0.5, 8); pe <- runif(1, 0.05, 0.3); sg <- runif(1, 0.2, 1.0); ord <- sample(1:3, 1); dg <- sample(1:3, 1)
  kn <- besseldot(sg, ord, dg)
  if (sv == 5) {
    x <- rbind(matrix(rnorm(n1 * p, -0.6, 0.8), n1), matrix(rnorm((n - n1) * p, 0.6, 0.8), n - n1))
    yf <- factor(rep(1:2, c(n1, n - n1))); yd <- ifelse(as.integer(yf) == 1, -1, 1)
    m <- ksvm(x, yf, type = "C-bsvc", kernel = kn, C = C, scaled = FALSE)
    full <- numeric(n); full[alphaindex(m)[[1]]] <- coef(m)[[1]]
  } else {
    x <- matrix(rnorm(n * p), n); yd <- sin(x[, 1]) + 0.1 * rnorm(n)
    m <- ksvm(x, yd, type = "eps-bsvr", kernel = kn, C = C, epsilon = pe, scaled = FALSE)
    full <- numeric(n); full[alphaindex(m)] <- coef(m)
  }
  K <- as.matrix(kernelMatrix(kn, x)); dec <- as.vector(K %*% full - b(m))
  a <- c(n, p, 6, sv, C, pe, sg, ord, dg, yd, as.vector(t(x)))
  add("alpha", a, ws(full)); add("b", a, b(m)); add("obj", a, obj(m)); add("dec", a, ws(dec), rel = 1e-8)
}
for (rep in 1:9) {
  sv <- c(7, 8, 5)[(rep - 1) %% 3 + 1]; K <- 3; p <- sample(2:3, 1); per <- sample(7:11, 1); n <- K * per
  C <- runif(1, 0.5, 8); sg <- runif(1, 0.2, 1.0); ord <- sample(1:3, 1); dg <- sample(1:3, 1)
  ctr <- matrix(rnorm(K * p, 0, 1.2), K); cls0 <- rep(1:K, per)[sample(n)]
  x0 <- ctr[cls0, , drop = FALSE] + matrix(rnorm(n * p, 0, 1), n); xt <- matrix(rnorm(8 * p, 0, 1.5), 8)
  type <- c("5" = "C-bsvc", "7" = "spoc-svc", "8" = "kbb-svc")[as.character(sv)]
  m <- ksvm(x0, factor(cls0), type = type, kernel = besseldot(sg, ord, dg), C = C, scaled = FALSE)
  ix <- if (sv == 5) order(cls0, method = "radix") else sort(cls0, method = "quick", index.return = TRUE)$ix
  x <- x0[ix, , drop = FALSE]; cls <- cls0[ix]
  a <- c(n, p, K, 6, sv, C, sg, ord, dg, nrow(xt), cls - 1, as.vector(t(x)), as.vector(t(xt)))
  pr <- as.integer(predict(m, xt))
  if (sv == 5) {
    full <- unlist(lapply(seq_along(alphaindex(m)), function(q) { f <- numeric(n); f[match(alphaindex(m)[[q]], ix)] <- coef(m)[[q]]; f }))
    add("alpha", a, ws(full)); add("b", a, ws(b(m))); add("obj", a, sum(obj(m)))
  } else {
    raw <- alpha(m)[ix, , drop = FALSE]
    gcell <- if (sv == 7) raw[n %/% K + 1, n %% K + 1] else raw[1, 2]
    garbage <- abs(gcell) > 1e-200
    if (sv == 7) raw[n %/% K + 1, n %% K + 1] <- 0 else raw[1, 2] <- 0
    add("alpha", a, ws(t(raw)))
    if (sv == 8) add("b", a, ws(-colSums(raw)))
  }
  if (!(sv %in% c(7, 8)) || !garbage) add("resp", a, ws(pr))
}
emit("kernlabbsvm", "kernlab", list(cases))
