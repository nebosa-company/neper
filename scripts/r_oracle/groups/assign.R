# clue::solve_LSAP and lpSolve::lp.assign against e.algo.graph.match.hungarian (minimum cost, square matrices).
#   args: (n, cost row-major n by n...)   fn "cost" (the minimum total cost) "perm" (the assignment weighted by row)
suppressMessages({library(clue); library(lpSolve)})
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-10)
set.seed(20261230)
for (rep in 1:30) {
  n <- sample(2:9, 1); m <- matrix(round(runif(n * n, 0, 50), 3), n, n)
  s <- as.integer(solve_LSAP(m)); l <- lp.assign(m)
  add("cost", c(n, as.vector(t(m))), sum(m[cbind(1:n, s)]))
  add("perm", c(n, as.vector(t(m))), sum(s * seq_len(n)))
  add("lpcost", c(n, as.vector(t(m))), l$objval)
}
emit("assign", "clue", list(cases))
