# irlba::irlba with the deflation (list) form of v: a first fit s1 = irlba(x, k1), then irlba(x, k2, v = s1). Args: (m, n, k1, k2, smallest, seed1, seed2, kind, x[m * n] column-major); kind 0 d, 1 u, 2 v (weighted sums, sign-exact), 3 iter, 4 mprod
suppressMessages(library(irlba))
cases <- list()
set.seed(20262404)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("irlbadefl", args, want, rel = 1e-7, abs = 1e-9)
w <- function(M) sum(M * seq_along(M))
for (rep in 1:14) {
  m <- sample(24:40, 1); n <- sample(10:16, 1); if (rep %% 4 == 0) { t <- m; m <- n; n <- t }
  k1 <- sample(2:3, 1); k2 <- sample(2:3, 1); sm <- 0L
  X <- matrix(round(rnorm(m * n) * runif(n, 0.5, 2), 4), m)
  s1 <- sample(1:100000, 1); s2 <- sample(1:100000, 1)
  set.seed(s1); f1 <- tryCatch(suppressWarnings(irlba(X, k1, smallest = sm == 1)), error = function(e) NULL)
  if (is.null(f1)) next
  set.seed(s2); r <- tryCatch(suppressWarnings(irlba(X, k2, smallest = sm == 1, v = f1)), error = function(e) NULL)
  if (is.null(r)) next
  a <- function(kind) c(m, n, k1, k2, sm, s1, s2, kind, as.vector(X))
  add(a(0), w(r$d)); add(a(1), w(r$u)); add(a(2), w(r$v)); add(a(3), r$iter); add(a(4), r$mprod)
}
emit("irlba_defl", "irlba", list(cases))
