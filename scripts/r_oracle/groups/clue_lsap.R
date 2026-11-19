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
emit("clue_lsap", "clue", list(cases))
