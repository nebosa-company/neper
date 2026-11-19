# irlba::irlba under set.seed: d, u, v (sign-exact, position-weighted sums), iter and mprod. Args: (m, n, nv, nu, work, tol, smallest, center, scale, hasshift, shift, maxit, seed, kind, x[m * n] column-major, center vector[n], scale vector[n]); kind 0 d, 1 u, 2 v, 3 iter, 4 mprod.
suppressMessages(library(irlba))
cases <- list()
set.seed(20262401)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("irlba", args, want, rel = 1e-7, abs = 1e-9)
w <- function(M) sum(M * seq_along(M))
for (rep in 1:36) {
  m <- sample(24:44, 1); n <- sample(9:16, 1)
  if (rep %% 4 == 0) { t <- m; m <- n; n <- t }
  nv <- sample(2:4, 1); nu <- if (rep %% 3 == 0) max(1, nv - 1) else nv
  work <- nv + sample(3:7, 1); tol <- c(1e-7, 1e-5, 1e-9)[sample(3, 1)]
  smallest <- as.integer(rep %% 5 == 0); cen <- as.integer(rep %% 2 == 0); sc <- as.integer(rep %% 6 == 0)
  hs <- as.integer(m == n && rep %% 7 == 0); sh <- if (hs) round(runif(1, 0.5, 3), 3) else 0
  maxit <- if (rep %% 9 == 0) 3 else 1000
  X <- matrix(round(rnorm(m * n) * runif(n, 0.5, 2), 4), m)
  sd1 <- sample(1:100000, 1)
  args <- list(A = X, nv = nv, nu = nu, work = work, tol = tol, smallest = smallest == 1, maxit = maxit)
  if (cen) args$center <- colMeans(X)
  if (sc) args$scale <- apply(X, 2, function(v) sqrt(sum((v - if (cen) mean(v) else 0)^2) / (m - 1)))
  if (hs) args$shift <- sh
  set.seed(sd1)
  r <- tryCatch(suppressWarnings(do.call(irlba, args)), error = function(e) NULL)
  if (is.null(r)) next
  cenv <- if (cen) args$center else rep(0, n); scv <- if (sc) args$scale else rep(1, n)
  a <- function(kind) c(m, n, nv, nu, work, tol, smallest, cen, sc, hs, sh, maxit, sd1, kind, as.vector(X), cenv, scv)
  add(a(0), w(r$d)); add(a(1), w(r$u)); add(a(2), w(r$v)); add(a(3), r$iter); add(a(4), r$mprod)
}
emit("irlba", "irlba", list(cases))
