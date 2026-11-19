# lpSolveAPI: model edits and readers against e.algo.stat.lpsolveapi: set.mat, set.rhs, set.constr.type, set.row, set.column, delete.constraint, delete.column, add.column,
# set.bounds, set.type, set.objfn, then dim, get.mat, get.rhs, get.constr.type, get.type, get.bounds, solve and get.objective.
#   args: (sense 0 min 1 max, m, n, c[n], A row-major, rel[m] (0 <=, 1 >=, 2 =), b[m], nops, ops...) each op 16 numbers: code, i, j, val, vec[12]
#   codes: 1 set.mat(i, j, val)  2 set.rhs(i, val)  3 set.constr.type(i, val)  4 set.row(i, vec[1..n])  5 set.column(j, vec[1..m])  6 delete.constraint(i)
#          7 delete.column(j)  8 add.column(vec[1..m])  9 set.bounds(j, 0, val)  10 set.type(j, val 1 integer)  11 set.objfn(vec[1..n])
#   fn "dimm" "dimn" (rows, columns after the edits), "mat" (sum of get.mat(i, j) * (100 (i + 1) + j) over i = 0..m, j = 1..n), "rhs" (get.rhs weighted by row),
#   "ctype" (get.constr.type code weighted by row), "ktype" (get.type, 1 for integer, weighted by column), "blo" "bhi" (get.bounds weighted by column, 1e30 for Inf), "status" and "obj".
suppressMessages(library(lpSolveAPI))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-9)
relstr <- c("<=", ">=", "=")
V <- 12
op <- function(code, i = 0, j = 0, val = 0, vec = numeric(0)) c(code, i, j, val, c(vec, rep(0, V - length(vec))))
set.seed(20262602)
made <- 0
for (rep in 1:400) {
  n <- sample(2:5, 1); m <- sample(2:5, 1); sense <- sample(0:1, 1)
  cc <- round(runif(n, -1, 4), 2)
  A <- matrix(round(runif(m * n, 0, 3), 2), m, n); rel <- sample(0:1, m, TRUE); b <- round(runif(m, 2, 10), 2)
  lp0 <- make.lp(0, n); lp.control(lp0, sense = if (sense == 1) "max" else "min"); set.objfn(lp0, cc)
  for (i in seq_len(m)) add.constraint(lp0, A[i, ], relstr[rel[i] + 1], b[i])
  set.bounds(lp0, lower = rep(0, n), upper = rep(10, n))
  ops <- list(); cm <- m; cn <- n
  for (k in 1:sample(2:6, 1)) {
    code <- sample(1:11, 1)
    if (code == 1) { i <- sample(0:cm, 1); j <- sample(cn, 1); v <- round(runif(1, 0, 3), 2); set.mat(lp0, i, j, v); ops[[k]] <- op(1, i, j, v) }
    else if (code == 2) { i <- sample(cm, 1); v <- round(runif(1, 2, 10), 2); set.rhs(lp0, v, i); ops[[k]] <- op(2, i, 0, v) }
    else if (code == 3) { i <- sample(cm, 1); v <- sample(0:2, 1); set.constr.type(lp0, relstr[v + 1], i); ops[[k]] <- op(3, i, 0, v) }
    else if (code == 4) { i <- sample(cm, 1); v <- round(runif(cn, 0, 3), 2); set.row(lp0, i, v); ops[[k]] <- op(4, i, 0, 0, v) }
    else if (code == 5) { j <- sample(cn, 1); v <- round(runif(cm, 0, 3), 2); set.column(lp0, j, v, seq_len(cm)); ops[[k]] <- op(5, 0, j, 0, v) }
    else if (code == 6) { if (cm < 2) { ops[[k]] <- NULL; next }; i <- sample(cm, 1); delete.constraint(lp0, i); cm <- cm - 1; ops[[k]] <- op(6, i) }
    else if (code == 7) { if (cn < 2) { ops[[k]] <- NULL; next }; j <- sample(cn, 1); delete.column(lp0, j); cn <- cn - 1; ops[[k]] <- op(7, 0, j) }
    else if (code == 8) { if (cn >= 7) { ops[[k]] <- NULL; next }; v <- round(runif(cm, 0, 3), 2); add.column(lp0, v, seq_len(cm)); cn <- cn + 1; ops[[k]] <- op(8, 0, 0, 0, v) }
    else if (code == 9) { j <- sample(cn, 1); v <- sample(3:12, 1); set.bounds(lp0, lower = 0, upper = v, columns = j); ops[[k]] <- op(9, 0, j, v) }
    else if (code == 10) { j <- sample(cn, 1); set.type(lp0, j, "integer"); ops[[k]] <- op(10, 0, j, 1) }
    else { v <- round(runif(cn, -1, 4), 2); set.objfn(lp0, v); ops[[k]] <- op(11, 0, 0, 0, v) }
  }
  ops <- Filter(Negate(is.null), ops)
  a <- c(sense, m, n, cc, as.vector(t(A)), rel, b, length(ops), unlist(ops))
  nr <- dim(lp0)[1]; nc <- dim(lp0)[2]
  stopifnot(nr == cm, nc == cn)
  add("dimm", a, nr); add("dimn", a, nc)
  ms <- 0
  for (i in 0:nr) for (j in seq_len(nc)) ms <- ms + get.mat(lp0, i, j) * (100 * (i + 1) + j)
  add("mat", a, ms)
  add("rhs", a, sum(get.rhs(lp0) * seq_len(nr)))
  add("ctype", a, sum((match(get.constr.type(lp0), relstr) - 1) * seq_len(nr)))
  add("ktype", a, sum((get.type(lp0) == "integer") * seq_len(nc)))
  bd <- get.bounds(lp0); cl <- function(v) pmax(pmin(v, 1e30), -1e30)
  add("blo", a, sum(cl(bd$lower) * seq_len(nc))); add("bhi", a, sum(cl(bd$upper) * seq_len(nc)))
  st <- solve(lp0)
  add("status", a, st)
  if (st == 0 && sum((get.type(lp0) == "integer")) == 0) add("obj", a, get.objective(lp0))
  made <- made + 1
  if (made >= 80) break
}
emit("lpsolveapi_edit", "lpSolveAPI", list(cases))
