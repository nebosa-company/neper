# energy: dcov, dcor (with an index exponent) and the two-sample energy statistic.
#   args: (n, dx, dy, index, x row-major n by dx..., y row-major n by dy...)   fn "dcov" "dcor"
#   args: (n1, n2, d, index, x row-major..., y row-major...)   fn "edist" (edist and the eqdist.etest statistic agree)
suppressMessages(library(energy))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261222)
for (rep in 1:16) {
  n <- sample(8:35, 1); dx <- sample(1:3, 1); dy <- sample(1:3, 1); idx <- c(1, 0.5, 1.5, 1)[rep %% 4 + 1]
  x <- matrix(rnorm(n * dx), n, dx); y <- matrix(rnorm(n * dy) + x[, 1], n, dy)
  a <- c(n, dx, dy, idx, as.vector(t(x)), as.vector(t(y)))
  add("dcov", a, dcov(x, y, index = idx)); add("dcor", a, dcor(x, y, index = idx))
  n1 <- sample(6:20, 1); n2 <- sample(6:20, 1); d <- sample(1:3, 1)
  p <- matrix(rnorm(n1 * d), n1, d); q <- matrix(rnorm(n2 * d) + 0.5, n2, d)
  add("edist", c(n1, n2, d, idx, as.vector(t(p)), as.vector(t(q))), as.numeric(edist(rbind(p, q), sizes = c(n1, n2), alpha = idx)))
}
emit("energy", "energy", list(cases))
