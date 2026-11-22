# ks kcurv of kdde(x, H, deriv.order = 2, binned = FALSE) in one to three dimensions.
#   args: (d, n, which, idx, m, H d*d, x row-major...); which 0 = curvature at grid index idx (0-based, first variable fastest), 1 = contour level at cont = idx
suppressMessages(library(ks))
cases <- list()
add <- function(fn, args, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-13)
rowvec <- function(m) as.vector(t(m))
spd <- function(d) { B <- matrix(runif(d * d, -0.4, 0.4), d, d); crossprod(B) + diag(runif(d, 0.05, 0.3), d) }
mkx <- function(n, d) { A <- matrix(runif(d * d, -1, 1), d, d); round(matrix(rnorm(n * d), n, d) %*% A, 5) }
msize <- c(401, 151, 51)
set.seed(20262013)
for (d in 1:3) for (rep in 1:3) {
  n <- sample(40:80, 1)
  x <- mkx(n, d); H <- spd(d)
  f <- if (d == 1) kdde(as.vector(x), h = sqrt(H[1, 1]), deriv.order = 2, binned = FALSE) else kdde(x, H = H, deriv.order = 2, binned = FALSE)
  k <- kcurv(f, compute.cont = FALSE)
  est <- as.vector(k$estimate)
  pos <- which(est > 0)
  for (i in sample(pos, 6)) add("kcurv", c(d, n, 0, i - 1, msize[d], rowvec(H), rowvec(x)), est[i])
  add("kcurv", c(d, n, 0, sample(which(est == 0), 1) - 1, msize[d], rowvec(H), rowvec(x)), 0)
  if (d > 1) {
    kc <- kcurv(f, compute.cont = TRUE)
    for (ct in c(1, 25, 50, 75, 99)) add("kcurv", c(d, n, 1, ct, msize[d], rowvec(H), rowvec(x)), unname(kc$cont[ct]))
  }
}
emit("kscurv", "ks", list(cases))
