# clue::solve_LSAP (rectangular, maximum), cl_membership of hard partitions, lpSolve::lp.assign(direction = "max") against e.algo.stat.cluelsap.
#   "lsap" (nr, nc, maximum, x row-major...): the total cost of the matching; "lsapcols" the same args: the chosen columns weighted by row (1-based)
#   "member" (n, k, cx[n]...): sum over the n by k cl_membership matrix of entry * (10 * row + column); "lpmax" (n, x...): lp.assign(max)$objval
suppressMessages({library(clue); library(lpSolve)})
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-10)
set.seed(20262410)
for (rep in 1:60) {
  nr <- sample(1:8, 1); nc <- nr + sample(0:4, 1); mx <- sample(0:1, 1)
  x <- matrix(round(runif(nr * nc, 0, 50), 3), nr, nc)
  s <- as.integer(solve_LSAP(x, maximum = mx == 1))
  a <- c(nr, nc, mx, as.vector(t(x)))
  add("lsap", a, sum(x[cbind(seq_len(nr), s)]))
  add("lsapcols", a, sum(s * seq_len(nr)))
}
for (rep in 1:40) {
  n <- sample(2:9, 1); x <- matrix(round(runif(n * n, 0, 50), 3), n, n)
  add("lpmax", c(n, as.vector(t(x))), lp.assign(x, "max")$objval)
}
for (rep in 1:40) {
  n <- sample(6:30, 1); kc <- sample(2:5, 1); cx <- c(seq_len(kc), sample(seq_len(kc), n - kc, replace = TRUE))
  M <- unclass(cl_membership(as.cl_partition(factor(cx))))
  add("member", c(n, kc, cx), sum(M * outer(seq_len(n), seq_len(kc), function(i, j) 10 * i + j)))
}
# exact solution vectors: "lsapat" (same args as lsap, then i): the 1-based column solve_LSAP picks for row i, integer-valued matrices included (ties)
for (rep in 1:50) {
  nr <- sample(1:7, 1); nc <- nr + sample(0:3, 1); mx <- sample(0:1, 1)
  x <- matrix(sample(0:(if (rep %% 2 == 0) 4 else 60), nr * nc, TRUE), nr, nc)
  if (rep %% 2 == 1) x <- x + matrix(round(runif(nr * nc, 0, 0.5), 3), nr, nc)
  s <- as.integer(solve_LSAP(x, maximum = mx == 1))
  a <- c(nr, nc, mx, as.vector(t(x)))
  for (i in seq_len(nr)) add("lsapat", c(a, i), s[i])
}
# cl_membership(x, k) with k above the class count, hard (labels cx, then k) and soft (n, k0, k, u row-major)
# "memrow" (n, kc, k, cx...: row i) the entry-weighted column; "memcol" (same, column j) the column total; "softat" (n, k0, k, u..., i, j) the entry
for (rep in 1:40) {
  n <- sample(6:25, 1); kc <- sample(2:5, 1); k <- kc + sample(0:3, 1)
  cx <- c(seq_len(kc), sample(seq_len(kc), n - kc, replace = TRUE))
  M <- unclass(cl_membership(as.cl_partition(factor(cx)), k))
  a <- c(n, kc, k, cx)
  for (i in seq_len(n)) add("memrow", c(a, i), sum(M[i, ] * seq_len(k)))
  for (j in seq_len(k)) add("memcol", c(a, j), sum(M[, j]))
}
for (rep in 1:30) {
  n <- sample(4:12, 1); k0 <- sample(2:4, 1); k <- k0 + sample(0:3, 1)
  U <- matrix(runif(n * k0), n, k0); U <- U / rowSums(U)
  M <- unclass(cl_membership(as.cl_partition(U), k))
  a <- c(n, k0, k, as.vector(t(U)))
  for (i in seq_len(n)) for (j in seq_len(k)) add("softat", c(a, i, j), M[i, j])
}
# padding constant: nr < nc, maximum, entries of one huge scale plus perturbations at the rounding granularity of 2 * sum(x) (pad and max(x) - x round differently under another pad)
for (rep in 1:120) {
  nr <- sample(2:5, 1); nc <- nr + sample(1:3, 1)
  s <- 10^sample(3:8, 1)
  x <- matrix(s * round(runif(nr * nc, 0.9, 1), 2) + s * 1e-16 * sample(0:40, nr * nc, TRUE), nr, nc)
  a <- c(nr, nc, 1, as.vector(t(x)))
  sol <- as.integer(solve_LSAP(x, maximum = TRUE))
  for (i in seq_len(nr)) add("lsapat", c(a, i), sol[i])
}
emit("clue_lsap", "clue", list(cases))
