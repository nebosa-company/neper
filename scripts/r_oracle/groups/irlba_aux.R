# irlba::svdr, partial_eigen and prcomp_irlba under set.seed, sign-exact (position-weighted sums of d, u, v). Args by mode a[1]:
# 0 svdr: (0, m, n, k, extra, seed, kind, center, center vector[n], x[m * n] column-major); kind 0 d, 1 u, 2 v, 3 mprod
# 1 partial_eigen: (1, n, nev, seed, kind, symmetric, x[n * n]); kind 0 values, 1 vectors
# 2 prcomp_irlba: (2, m, p, nv, center, scale, seed, kind, x[m * p]); kind 0 sdev, 1 totalvar, 2 rotation, 3 scores
suppressMessages(library(irlba))
cases <- list()
set.seed(20262402)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("irlbaux", args, want, rel = 1e-9, abs = 1e-11)
w <- function(M) sum(M * seq_along(M))
for (rep in 1:14) {
  m <- sample(20:40, 1); n <- sample(8:14, 1); k <- sample(2:4, 1); ex <- sample(3:7, 1); cen <- rep %% 2
  X <- matrix(round(rnorm(m * n) * runif(n, 0.5, 2), 4), m)
  cv <- if (cen) colMeans(X) else rep(0, n)
  sd1 <- sample(1:100000, 1)
  set.seed(sd1)
  r <- svdr(X, k, extra = ex, center = if (cen) cv else NULL)
  a <- function(kind) c(0, m, n, k, ex, sd1, kind, cen, cv, as.vector(X))
  add(a(0), w(r$d)); add(a(1), w(r$u)); add(a(2), w(r$v)); add(a(3), r$mprod)
}
for (rep in 1:10) {
  n <- sample(20:30, 1); nev <- sample(2:4, 1); sym <- as.integer(rep %% 5 != 0)
  Z <- matrix(round(rnorm(n * n), 3), n)
  S <- if (sym) { M <- Z + t(Z); if (rep %% 2 == 0) M %*% M / n else M } else Z
  S <- round(S, 4)
  sd1 <- sample(1:100000, 1)
  set.seed(sd1)
  r <- tryCatch(suppressWarnings(partial_eigen(S, nev, symmetric = sym == 1)), error = function(e) NULL)
  if (is.null(r)) next
  a <- function(kind) c(1, n, nev, sd1, kind, sym, as.vector(S))
  add(a(0), w(r$values)); add(a(1), w(r$vectors))
}
for (rep in 1:12) {
  m <- sample(30:50, 1); p <- sample(8:14, 1); nv <- sample(2:4, 1); cen <- as.integer(rep %% 2 == 0); sc <- as.integer(rep %% 3 == 0)
  X <- matrix(round(rnorm(m * p) * runif(p, 0.5, 2) + runif(p, 0, 3), 4), m)
  sd1 <- sample(1:100000, 1)
  set.seed(sd1)
  r <- tryCatch(suppressWarnings(prcomp_irlba(X, n = nv, center = cen == 1, scale. = sc == 1)), error = function(e) NULL)
  if (is.null(r)) next
  a <- function(kind) c(2, m, p, nv, cen, sc, sd1, kind, as.vector(X))
  add(a(0), w(r$sdev)); add(a(1), r$totalvar); add(a(2), w(r$rotation)); add(a(3), w(r$x))
}
# 3 ssvd: (3, m, p, k, nsp, center, scale, seed, kind, x[m * p]); kind 0 d (k x k), 1 u, 2 v, 3 iter, 4 lambda
for (rep in 1:10) {
  m <- sample(30:45, 1); p <- sample(8:12, 1); k <- sample(1:2, 1); nsp <- sample(2:4, 1); cen <- as.integer(rep %% 2 == 0); sc <- as.integer(rep %% 3 == 0)
  X <- matrix(round(rnorm(m * p) * runif(p, 0.5, 2) + runif(p, 0, 2), 4), m)
  sd1 <- sample(1:100000, 1)
  set.seed(sd1)
  r <- tryCatch(suppressWarnings(ssvd(X, k = k, n = nsp, center = cen == 1, scale. = sc == 1)), error = function(e) NULL)
  if (is.null(r)) next
  a <- function(kind) c(3, m, p, k, nsp, cen, sc, sd1, kind, as.vector(X))
  add(a(0), w(r$d)); add(a(1), w(r$u)); add(a(2), w(r$v)); add(a(3), r$iter); add(a(4), w(r$lambda))
}
emit("irlba_aux", "irlba", list(cases))
