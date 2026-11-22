# ks kde.local.test, exact estimation, bandwidths given, in one to three dimensions.
#   args: (d, n1, n2, m, mean.adj, which, cell, H1 d*d, H2 d*d, x1 row-major, x2 row-major)
#   which: 0 positive cells, 1 negative cells, 2 fhat.diff[cell], 3 var.fhat.diff[cell], 4 chi-square[cell], 5 pvalue[cell]
suppressMessages(library(ks))
cases <- list()
add <- function(fn, args, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-13)
rowvec <- function(m) as.vector(t(m))
spd <- function(d) { B <- matrix(runif(d * d, -0.4, 0.4), d, d); crossprod(B) + diag(runif(d, 0.05, 0.3), d) }
mkx <- function(n, d, shift) { A <- matrix(runif(d * d, -1, 1), d, d); round(matrix(rnorm(n * d), n, d) %*% A + shift, 5) }
msize <- c(401, 151, 51)
set.seed(20262012)
for (d in 1:3) for (ma in c(FALSE, TRUE)) for (rep in 1:2) {
  n1 <- sample(30:60, 1); n2 <- sample(30:60, 1)
  x1 <- mkx(n1, d, 0); x2 <- mkx(n2, d, 0.4)
  H1 <- spd(d); H2 <- spd(d)
  r <- if (d == 1) kde.local.test(as.vector(x1), as.vector(x2), h1 = sqrt(H1[1, 1]), h2 = sqrt(H2[1, 1]), binned = FALSE, mean.adj = ma) else kde.local.test(x1, x2, H1 = H1, H2 = H2, binned = FALSE, mean.adj = ma)
  X2 <- if (is.null(r$X2)) r$chisq else r$X2
  base <- c(d, n1, n2, msize[d], ma)
  tail <- c(rowvec(H1), rowvec(H2), rowvec(x1), rowvec(x2))
  add("lt", c(base, 0, 0, tail), sum(r$fhat.diff.pos$estimate > 0))
  add("lt", c(base, 1, 0, tail), sum(r$fhat.diff.neg$estimate > 0))
  ok <- which(is.finite(as.vector(X2)) & as.vector(r$var.fhat.diff) > 1e-8)
  for (k in sample(ok, 5)) {
    add("lt", c(base, 2, k - 1, tail), as.vector(r$fhat.diff)[k])
    add("lt", c(base, 3, k - 1, tail), as.vector(r$var.fhat.diff)[k])
    add("lt", c(base, 4, k - 1, tail), as.vector(X2)[k])
    add("lt", c(base, 5, k - 1, tail), as.vector(r$pvalue)[k])
  }
}
emit("kslocal", "ks", list(cases))
