# e1071::rwiener and cmeans (given centres, euclidean): under set.seed.
#   rw: (seed, n, freq, i)  fn "w" element i;   cm: (seed, n, nc, k, m, w..., x[n*nc] column-major, centres[k*nc] column-major, q)  fn "c"
#   q 0..k*nc-1 centres (column-major), then withinerror, iter, then u summaries: sum of u*(row index), u of cell (0,0) ... all memberships follow
suppressMessages(library(e1071))
cases <- list()
add <- function(fn, args, want, tol = 1e-8) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = tol, abs = 1e-10)
set.seed(20261116)
for (sd in 1:4) { set.seed(sd); w <- as.numeric(rwiener(end = 1, frequency = 60)); for (i in c(1, 10, 30, 60)) add("w", c(sd, 60, 60, i - 1), w[i]) }
for (rep in 1:20) {
  n <- sample(30:90, 1); nc <- sample(1:3, 1); k <- sample(2:4, 1); m <- c(1.5, 2, 2.5)[rep %% 3 + 1]
  cl <- sample(1:k, n, TRUE); x <- matrix(rnorm(n * nc) * 0.7 + cl, n, nc); x <- round(x, 3)
  cen <- x[sample(n, k), , drop = FALSE]; wt <- if (rep %% 2 == 0) round(runif(n, 0.5, 2), 3) else rep(1, n)
  sd <- rep
  set.seed(sd); r <- cmeans(x, cen, iter.max = 100, m = m, weights = wt)
  out <- c(as.vector(r$centers), r$withinerror, r$iter, as.vector(r$membership))
  a <- c(sd, n, nc, k, m, wt, as.vector(x), as.vector(cen))
  for (q in seq_along(out)) add("c", c(a, q - 1), out[q])
}
emit("cmeans", "e1071", list(cases))
