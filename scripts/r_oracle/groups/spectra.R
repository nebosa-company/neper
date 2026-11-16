# RSpectra svds and eigs_sym, irlba, on random dense matrices; vectors are compared up to sign (absolute values).
#   args: (kind, m, n, k, which, x row-major m*n); kind 0 svds, 1 eigs_sym (m = n), 2 irlba
#   fn "d" (values weighted by position), "uabs" (sum of |u| entries weighted by position), "vabs" (same for v)
suppressMessages({library(RSpectra); library(irlba)})
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-6, abs = 1e-8)
set.seed(20261205)
ws <- function(x) sum(as.vector(x) * seq_along(x))
for (rep in 1:30) {
  kind <- (rep - 1) %% 3
  if (kind == 2) { m <- sample(20:30, 1); n <- sample(14:18, 1); x <- matrix(rnorm(m * n), m) } else if (kind == 1) { n <- sample(5:12, 1); m <- n; B <- matrix(rnorm(n * n), n); x <- (B + t(B)) / 2 } else { m <- sample(8:20, 1); n <- sample(5:min(m, 12), 1); x <- matrix(rnorm(m * n), m) }
  k <- sample(1:min(3, n - 2), 1); wh <- if (kind == 1) sample(0:3, 1) else 0
  a <- c(kind, m, n, k, wh, as.vector(t(x)))
  if (kind == 2) { m <- sample(20:30, 1); n <- sample(14:18, 1); x <- matrix(rnorm(m * n), m) } else if (kind == 1) {
    o <- eigs_sym(x, k, which = c("LM", "LA", "SA", "SM")[wh + 1], opts = list(tol = 1e-14, maxitr = 5000))
    add("d", a, ws(o$values)); add("uabs", a, ws(abs(o$vectors)))
  } else if (kind == 0) {
    o <- svds(x, k, opts = list(tol = 1e-14, maxitr = 5000))
    add("d", a, ws(o$d)); add("uabs", a, ws(abs(o$u))); add("vabs", a, ws(abs(o$v)))
  } else {
    o <- irlba(x, nv = k, tol = 1e-9, maxit = 5000)
    add("d", a, ws(o$d)); add("uabs", a, ws(abs(o$u))); add("vabs", a, ws(abs(o$v)))
  }
}
emit("spectra", c("RSpectra", "irlba"), list(cases))
