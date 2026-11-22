# kernlab kernelMatrix for seven kernels and kpca (rbf) on random data, kpca eigenvectors and rotated projections with LAPACK's signs.
#   args: (n, p, kind, par1, par2, par3, k, x[n*p] row-major)
#   fn "kmat" (kernel matrix weighted by position), "eig" "pcv" "rotated" (kpca with k features, rbfdot(par1))
suppressMessages(library(kernlab))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-11)
ws <- function(v) sum(as.vector(v) * seq_along(v))
rowmajor <- function(m) as.vector(t(m))
set.seed(20261227)
for (rep in 1:28) {
  n <- sample(8:30, 1); p <- sample(2:5, 1); kind <- (rep - 1) %% 7; x <- matrix(rnorm(n * p), n)
  pars <- c(runif(1, 0.2, 1.5), sample(1:3, 1), runif(1, 0, 1)); kk <- NULL
  kn <- switch(kind + 1, rbfdot(pars[1]), polydot(pars[2], pars[1], pars[3]), vanilladot(), tanhdot(pars[1] * 0.3, pars[3] - 0.5), laplacedot(pars[1]), anovadot(pars[1], pars[2]), splinedot())
  a <- c(n, p, kind, pars, 3, rowmajor(x))
  K <- as.matrix(kernelMatrix(kn, x)); add("kmat", a, ws(rowmajor(K)))
  if (kind == 0) {
    pc <- kpca(x, kernel = "rbfdot", kpar = list(sigma = pars[1]), features = 3)
    add("eig", a, ws(eig(pc))); add("pcv", a, ws(rowmajor(pcv(pc)))); add("rotated", a, ws(rowmajor(rotated(pc))))
  }
}
# besseldot(sigma = par1, order = par2, degree = par3): kind 7, kernelMatrix of the training set
for (rep in 1:16) {
  n <- sample(8:25, 1); p <- sample(2:4, 1); x <- matrix(rnorm(n * p), n)
  sg <- runif(1, 0.2, 1.0); ord <- sample(0:3, 1); dg <- sample(1:3, 1)
  K <- as.matrix(kernelMatrix(besseldot(sg, ord, dg), x))
  add("kmat", c(n, p, 7, sg, ord, dg, 3, rowmajor(x)), ws(rowmajor(K)))
}
emit("kernlab", "kernlab", list(cases))
