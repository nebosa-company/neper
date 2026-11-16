# kernlab kernelMatrix for seven kernels and kpca (rbf) on random data; kpca vectors compared as absolute values.
#   args: (n, p, kind, par1, par2, par3, k, x[n*p] row-major)
#   fn "kmat" (kernel matrix weighted by position), "eig" "pcv" "rotated" (kpca with k features, rbfdot(par1))
suppressMessages(library(kernlab))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-7, abs = 1e-9)
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
    add("eig", a, ws(eig(pc))); add("pcv", a, ws(abs(rowmajor(pcv(pc))))); add("rotated", a, ws(abs(rowmajor(rotated(pc)))))
  }
}
emit("kernlab", "kernlab", list(cases))
