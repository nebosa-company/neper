# lpSolve: lp("max", ...) with <= and >= rows against e.math.opt.simplex (the >= rows are given to the simplex negated).
#   args: (m, n, c[n]..., A row-major m by n..., rel[m]... (0 for <=, 1 for >=), b[m]...)   fn "obj" (the optimum) "x" (the solution weighted by position)
suppressMessages(library(lpSolve))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-9)
set.seed(20261229)
rep_ok <- 0
for (rep in 1:60) {
  n <- sample(2:5, 1); m <- sample(2:6, 1)
  cc <- round(runif(n, -1, 4), 2)
  A <- matrix(round(runif(m * n, -1, 4), 2), m, n); b <- round(runif(m, 3, 20), 2); rel <- sample(c("<=", "<=", ">="), m, replace = TRUE)
  A <- rbind(A, rep(1, n)); b <- c(b, 30); rel <- c(rel, "<=")
  if (any(rel == ">=")) b[rel == ">="] <- round(b[rel == ">="] / 10, 2)
  s <- lp("max", cc, A, rel, b)
  if (s$status != 0) next
  m1 <- nrow(A)
  add("obj", c(m1, n, cc, as.vector(t(A)), as.numeric(rel == ">="), b), s$objval)
  add("x", c(m1, n, cc, as.vector(t(A)), as.numeric(rel == ">="), b), sum(s$solution * seq_len(n)))
  rep_ok <- rep_ok + 1
  if (rep_ok >= 30) break
}
# equality rows (rel code 2): lp("max", ...) with "=" rows built around a feasible point
rep_eq <- 0
for (rep in 1:200) {
  n <- sample(3:5, 1); me <- sample(1:2, 1); mi <- sample(2:4, 1)
  cc <- round(runif(n, -1, 4), 2)
  x0 <- round(runif(n, 0.5, 3), 2)
  Ae <- matrix(round(runif(me * n, -1, 3), 2), me, n); be <- as.vector(Ae %*% x0)
  Ai <- matrix(round(runif(mi * n, 0, 3), 2), mi, n); bi <- as.vector(Ai %*% x0) + round(runif(mi, 0.5, 4), 2)
  A <- rbind(Ae, Ai, rep(1, n)); b <- c(be, bi, sum(x0) + 8); rel <- c(rep("=", me), rep("<=", mi), "<=")
  s <- lp("max", cc, A, rel, b)
  if (s$status != 0) next
  relc <- ifelse(rel == "=", 2, 0)
  add("obj", c(nrow(A), n, cc, as.vector(t(A)), relc, b), s$objval)
  add("x", c(nrow(A), n, cc, as.vector(t(A)), relc, b), sum(s$solution * seq_len(n)))
  rep_eq <- rep_eq + 1
  if (rep_eq >= 30) break
}
emit("lpsolve", "lpSolve", list(cases))
