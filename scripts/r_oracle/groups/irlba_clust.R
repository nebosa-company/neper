# irlba::irlba on matrices whose singular values sit in tight clusters, so the extended-gap guard (clustered Ritz values, maxritz and the work enlargement) is reached: d, u, v (sign-exact, position-weighted sums), iter and mprod.
# Args as irlba.R: (m, n, nv, nu, work, tol, smallest, center, scale, hasshift, shift, maxit, seed, kind, x[m * n] column-major, center vector[n], scale vector[n], reorth); kind 0 d, 1 u, 2 v, 3 iter, 4 mprod.
suppressMessages(library(irlba))
cases <- list()
set.seed(20262412)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("irlba_clust", args, want, rel = 1e-9, abs = 1e-11)
w <- function(M) sum(M * seq_along(M))
for (rep in 1:48) {
  m <- sample(30:44, 1); n <- sample(12:18, 1)
  nv <- sample(2:3, 1); work <- nv + sample(2:4, 1); tol <- c(1e-7, 1e-9, 1e-12)[sample(3, 1)]
  gap <- c(1e-10, 1e-9, 1e-7, 1e-5, 1e-4, 1e-3)[sample(6, 1)]
  s <- c(10, 6 + gap * (0:(n - 3)), 1)[1:n]
  Q1 <- qr.Q(qr(matrix(rnorm(m * n), m))); Q2 <- qr.Q(qr(matrix(rnorm(n * n), n)))
  X <- Q1 %*% (s * t(Q2))
  sd1 <- sample(1:100000, 1)
  set.seed(sd1)
  r <- tryCatch(suppressWarnings(irlba(X, nv = nv, nu = nv, work = work, tol = tol, maxit = 60)), error = function(e) NULL)
  if (is.null(r)) next
  cenv <- rep(0, n); scv <- rep(1, n)
  a <- function(kind) c(m, n, nv, nv, work, tol, 0, 0, 0, 0, 0, 60, sd1, kind, as.vector(X), cenv, scv, 1)
  add(a(0), w(r$d)); add(a(3), r$iter); add(a(4), r$mprod)
}
emit("irlba_clust", "irlba", list(cases))
