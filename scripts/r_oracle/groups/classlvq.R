# class: SOM, batchSOM, lvqinit, lvq1, lvq2, lvq3, olvq1 under set.seed.
#   som: (seed, hex, xdim, ydim, kind 0 SOM 1 batchSOM, given 0/1, n, p, rlen, data row-major[n*p], init row-major[ng*p] (given only), alpha[rlen], radii[rlen], q) fn "som"  q 0 sum 1 weighted sum of the codes
#   lvq: (seed, method 0 lvqinit 1 lvq1 2 lvq2 3 lvq3 4 olvq1, n, p, nc, size (-1 default), k, niter, alpha, win, eps, x row-major[n*p], cl[n], q) fn "lvq"  q 0 rows 1 sum 2 weighted sum of the codebook, 3 sum of the classes
suppressMessages(library(class))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-11)
rowmajor <- function(m) as.vector(t(m))
set.seed(20261118)
for (rep in 1:40) {
  n <- sample(40:120, 1); p <- sample(2:4, 1); xd <- sample(2:5, 1); yd <- sample(2:4, 1); hex <- sample(0:1, 1); kind <- sample(0:1, 1); given <- sample(0:1, 1)
  data <- matrix(rnorm(n * p), n, p); ng <- xd * yd
  rlen <- if (kind == 0) sample(20:150, 1) else sample(2:6, 1)
  alpha <- seq(0.05, 0, length.out = rlen); radii <- seq(4, 1, length.out = rlen)
  grid <- somgrid(xd, yd, c("rectangular", "hexagonal")[hex + 1])
  init <- data[sample(1:n, ng), , drop = FALSE]
  seed <- sample(1e6, 1); set.seed(seed)
  r <- if (kind == 0) { if (given) SOM(data, grid, rlen = rlen, alpha = alpha, radii = radii, init = init) else SOM(data, grid, rlen = rlen, alpha = alpha, radii = radii) }
       else { if (given) batchSOM(data, grid, radii = radii, init = init) else batchSOM(data, grid, radii = radii) }
  cd <- r$codes
  a <- c(seed, hex, xd, yd, kind, given, n, p, rlen, rowmajor(data), if (given) rowmajor(init), alpha, radii)
  add("som", c(a, 0), sum(cd)); add("som", c(a, 1), sum(seq_along(rowmajor(cd)) * rowmajor(cd)))
}
for (rep in 1:60) {
  nc <- sample(2:4, 1); p <- sample(2:4, 1); n <- sample(50:150, 1)
  cl <- factor(sample(seq_len(nc), n, TRUE)); x <- matrix(rnorm(n * p), n, p) + as.integer(cl) * 0.8
  seed <- sample(1e6, 1); method <- sample(0:4, 1); k <- sample(c(3, 5, 7), 1); niter <- sample(50:300, 1)
  size <- if (rep %% 3 == 0) sample(4:12, 1) else -1
  alpha <- c(0.03, 0.3, 0.3, 0.03, 0.3)[method + 1] * runif(1, 0.5, 1.5); win <- runif(1, 0.1, 0.5); eps <- runif(1, 0.05, 0.3)
  set.seed(seed)
  cb <- if (size > 0) lvqinit(x, cl, size = size, k = k) else lvqinit(x, cl, k = k)
  if (method > 0) cb <- switch(method, lvq1(x, cl, cb, niter, alpha), lvq2(x, cl, cb, niter, alpha, win), lvq3(x, cl, cb, niter, alpha, win, eps), olvq1(x, cl, cb, niter, alpha))
  a <- c(seed, method, n, p, nc, size, k, niter, alpha, win, eps, rowmajor(x), as.integer(cl))
  add("lvq", c(a, 0), nrow(cb$x)); add("lvq", c(a, 1), sum(cb$x)); add("lvq", c(a, 2), sum(seq_along(rowmajor(cb$x)) * rowmajor(cb$x))); add("lvq", c(a, 3), sum(as.integer(cb$cl)))
}
emit("classlvq", "class", list(cases))
