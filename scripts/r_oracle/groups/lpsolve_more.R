# lpSolve: lp("min"), the status codes of lp (2 infeasible, 3 unbounded), int.vec with min, lp.transport shipments and infeasible status, lp.assign("min").
#   "lpmin" (m, n, c[n], A row-major, rel[m] (0 <=, 1 >=, 2 =), b[m], isint[n]): the optimal value of lp("min", ..., int.vec)
#   "lpx" (same args): sum of solution * position (unique optima, continuous programs only)
#   "lpstat" (same args, direction code last: 0 min, 1 max): lp()$status
#   "trsol" (m, n, maximise, cost[m n], rsign[m], rrhs[m], csign[n], crhs[n]): the shipments weighted by 10 * row + col   "trstat": lp.transport()$status
#   "asmin" (n, x...): lp.assign(min)$objval   "asmincols" (n, x...): the solution matrix weighted by 10 * row + col
suppressMessages({library(lpSolve)})
cases <- list()
add <- function(fn, args, want, rel = 1e-8, abs = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
code <- function(v) match(v, c("<=", ">=", "=")) - 1
set.seed(20262601)
rep_ok <- 0
for (rep in 1:200) {
  n <- sample(2:5, 1); m <- sample(2:5, 1)
  cc <- round(runif(n, 0.5, 5), 2)
  A <- matrix(round(runif(m * n, 0.2, 4), 2), m, n); b <- round(runif(m, 2, 9), 2); rel <- sample(c(">=", ">=", "<="), m, replace = TRUE)
  A <- rbind(A, rep(1, n)); b <- c(b, 40); rel <- c(rel, "<=")
  s <- lp("min", cc, A, rel, b)
  if (s$status != 0) next
  args <- c(nrow(A), n, cc, as.vector(t(A)), code(rel), b, rep(0, n))
  add("lpmin", args, s$objval)
  add("lpx", args, sum(s$solution * seq_len(n)))
  add("lpstat", c(args, 0), 0)
  rep_ok <- rep_ok + 1
  if (rep_ok >= 25) break
}
# equality rows, min
rep_ok <- 0
for (rep in 1:200) {
  n <- sample(3:5, 1); me <- sample(1:2, 1)
  x0 <- round(runif(n, 0.5, 3), 2); cc <- round(runif(n, 0.5, 5), 2)
  Ae <- matrix(round(runif(me * n, 0.2, 3), 2), me, n); be <- as.vector(Ae %*% x0)
  A <- rbind(Ae, rep(1, n)); b <- c(be, sum(x0) + 6); rel <- c(rep("=", me), "<=")
  s <- lp("min", cc, A, rel, b)
  if (s$status != 0) next
  args <- c(nrow(A), n, cc, as.vector(t(A)), code(rel), b, rep(0, n))
  add("lpmin", args, s$objval); add("lpx", args, sum(s$solution * seq_len(n)))
  rep_ok <- rep_ok + 1
  if (rep_ok >= 15) break
}
# infeasible and unbounded programs, both directions
for (rep in 1:20) {
  n <- sample(2:4, 1); cc <- round(runif(n, 0.5, 4), 2)
  a1 <- round(runif(n, 0.5, 3), 2)
  lo <- round(runif(1, 5, 9), 2); hi <- lo - round(runif(1, 0.5, 3), 2)  # a.x >= lo and a.x <= hi with hi < lo
  A <- rbind(a1, a1); b <- c(lo, hi); rel <- c(">=", "<=")
  dirn <- sample(c("min", "max"), 1)
  s <- lp(dirn, cc, A, rel, b)
  add("lpstat", c(2, n, cc, as.vector(t(A)), code(rel), b, rep(0, n), as.numeric(dirn == "max")), s$status)
  b2 <- round(runif(1, 1, 5), 2)  # a single >= row: max is unbounded, min is bounded
  s2 <- lp(dirn, cc, matrix(a1, 1, n), ">=", b2)
  add("lpstat", c(1, n, cc, a1, 1, b2, rep(0, n), as.numeric(dirn == "max")), s2$status)
}
# integer programs, min direction: the true optimum by enumeration (lpSolve's value is checked to be at least that)
ok <- 0; nsub <- 0
for (rep in 1:300) {
  n <- sample(2:4, 1); m <- sample(1:3, 1)
  cc <- round(runif(n, 0.5, 5), 1)
  A <- matrix(round(runif(m * n, 0.5, 4), 1), m, n); b <- round(runif(m, 3, 12), 1); rel <- rep(">=", m)
  A <- rbind(A, diag(n)); b <- c(b, rep(5, n)); rel <- c(rel, rep("<=", n))
  ints <- sort(sample(seq_len(n), sample(1:n, 1)))
  s <- lp("min", cc, A, rel, b, int.vec = ints)
  if (s$status != 0) next
  grid <- as.matrix(expand.grid(lapply(ints, function(j) 0:5)))
  best <- Inf; cont <- setdiff(seq_len(n), ints)
  for (g in seq_len(nrow(grid))) {
    xi <- grid[g, ]; bb <- b - as.vector(A[, ints, drop = FALSE] %*% xi); base <- sum(cc[ints] * xi)
    if (length(cont) == 0) { if (all(ifelse(rel == "<=", bb >= -1e-9, bb <= 1e-9))) best <- min(best, base); next }
    sg <- lp("min", cc[cont], A[, cont, drop = FALSE], rel, bb)
    if (sg$status == 0) best <- min(best, base + sg$objval)
  }
  stopifnot(s$objval >= best - 1e-7)
  if (s$objval > best + 1e-7) nsub <- nsub + 1
  add("lpmin", c(nrow(A), n, cc, as.vector(t(A)), code(rel), b, as.numeric(seq_len(n) %in% ints)), best, 1e-8, 1e-8)
  ok <- ok + 1
  if (ok >= 40) break
}
cat("lpSolve above the true minimum in", nsub, "of", ok, "problems\n")
# lp.transport: shipments (random real costs, unique optimum) and the status of infeasible problems
nt <- 0
for (rep in 1:300) {
  m <- sample(2:4, 1); n <- sample(2:5, 1)
  cost <- matrix(round(runif(m * n, 1, 20), 3), m, n)
  sup <- sample(5:20, m, replace = TRUE); dem <- sample(3:15, n, replace = TRUE)
  mode <- rep %% 3
  rs <- if (mode == 0) rep("=", m) else rep("<=", m); cs <- if (mode == 1) rep(">=", n) else rep("=", n)
  if (mode == 0) { tot <- sum(sup); dem <- round(dem / sum(dem) * tot); dem[1] <- dem[1] + tot - sum(dem) }
  if (mode == 2) sup <- sup + 20
  dirn <- if (rep %% 2 == 0) "max" else "min"
  s <- tryCatch(lp.transport(cost, dirn, rs, sup, cs, dem), error = function(e) NULL)
  if (is.null(s) || s$status != 0) next
  a <- c(m, n, as.numeric(dirn == "max"), as.vector(t(cost)), code(rs), sup, code(cs), dem)
  add("trsol", a, sum(s$solution * outer(seq_len(m), seq_len(n), function(i, j) 10 * i + j)), 1e-7, 1e-7)
  add("trstat", a, 0)
  nt <- nt + 1
  if (nt >= 25) break
}
for (rep in 1:10) {  # infeasible: supplies (<=) cannot meet the demands (=)
  m <- sample(2:3, 1); n <- sample(2:4, 1)
  cost <- matrix(round(runif(m * n, 1, 20), 3), m, n); sup <- sample(2:5, m, replace = TRUE); dem <- sample(6:12, n, replace = TRUE)
  s <- lp.transport(cost, "min", rep("<=", m), sup, rep("=", n), dem)
  add("trstat", c(m, n, 0, as.vector(t(cost)), rep(0, m), sup, rep(2, n), dem), s$status)
}
# lp.transport(compute.sens = TRUE): the first m * n entries of lpSolve's duals, duals.from and duals.to (its wrapper reshapes the longer vector into the m by n matrix) and the sens.coef matrices,
# row-major; "trsens" takes the trsol arguments then (field, index): 0 duals, 1 duals.from, 2 duals.to, 3 sens.coef.from, 4 sens.coef.to.
# The unique solution is checked entry by entry ("trcell": the shipment of cell index).
nts <- 0
for (rep in 1:300) {
  m <- sample(2:4, 1); n <- sample(2:5, 1)
  cost <- matrix(round(runif(m * n, 1, 20), 3), m, n)
  sup <- sample(5:20, m, replace = TRUE); dem <- sample(3:15, n, replace = TRUE)
  mode <- 1 + (rep %/% 2) %% 2
  rs <- if (mode == 0) rep("=", m) else rep("<=", m); cs <- if (mode == 1) rep(">=", n) else rep("=", n)
  if (mode == 0) { tot <- sum(sup); dem <- round(dem / sum(dem) * tot); dem[1] <- dem[1] + tot - sum(dem) }
  if (mode == 2) sup <- sup + 20
  dirn <- if (rep %% 2 == 0) "max" else "min"
  s <- tryCatch(suppressWarnings(lp.transport(cost, dirn, rs, sup, cs, dem, compute.sens = TRUE)), error = function(e) NULL)
  if (is.null(s) || s$status != 0) next
  a <- c(m, n, as.numeric(dirn == "max"), as.vector(t(cost)), code(rs), sup, code(cs), dem)
  for (k in seq_len(m * n)) {
    add("trsens", c(a, 0, k), c(t(s$duals))[k]); add("trsens", c(a, 1, k), c(t(s$duals.from))[k]); add("trsens", c(a, 2, k), c(t(s$duals.to))[k])
    add("trsens", c(a, 3, k), c(t(s$sens.coef.from))[k]); add("trsens", c(a, 4, k), c(t(s$sens.coef.to))[k])
    add("trsens", c(a, 5, k), c(t(s$solution))[k])
  }
  nts <- nts + 1
  if (nts >= 8) break
}
# lp.assign: the full solution matrix entry by entry ("ascell": assigned flag of cell index, row-major), min and max ("asmax" objval)
for (rep in 1:25) {
  n <- sample(2:9, 1); x <- matrix(round(runif(n * n, 0, 50), 3), n, n)
  s <- lp.assign(x, "min")
  add("asmin", c(n, as.vector(t(x))), s$objval, 1e-9, 1e-9)
  for (k in seq_len(n * n)) add("ascell", c(n, 0, k, as.vector(t(x))), c(t(s$solution))[k], 1e-9, 1e-9)
  s2 <- lp.assign(x, "max")
  add("asmax", c(n, as.vector(t(x))), s2$objval, 1e-9, 1e-9)
  for (k in seq_len(n * n)) add("ascell", c(n, 1, k, as.vector(t(x))), c(t(s2$solution))[k], 1e-9, 1e-9)
}
emit("lpsolve_more", "lpSolve", list(cases))
