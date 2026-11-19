# lpSolveAPI: make.lp, set.objfn, add.constraint, set.bounds, set.type, lp.control(sense=) and solve against e.algo.stat.lpsolveapi.
#   args: (sense 0 min 1 max, m, n, c[n]..., A row-major m by n..., rel[m]... (0 <=, 1 >=, 2 =), b[m]..., lo[n]..., hi[n]... (+-1e30 for Inf), kind[n]... (0 real, 1 integer, 2 binary))
#   fn "status" (solve's code), "obj" (get.objective), "x" (get.variables weighted by position), "cons" (get.constraints weighted by position).
#   Linear programs are compared on all four. Pure integer and binary programs on status and obj, and only where lpSolveAPI's own answer equals a brute-force enumeration of the
#   integer grid (lp_solve's default branch and bound stops below the optimum on a few problems; those are left out, the count is printed).
suppressMessages(library(lpSolveAPI))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
inf <- 1e30
enc <- function(sense, A, relc, b, cc, lo, hi, kind) c(sense, nrow(A), ncol(A), cc, as.vector(t(A)), relc, b, pmax(pmin(lo, inf), -inf), pmax(pmin(hi, inf), -inf), kind)
relstr <- c("<=", ">=", "=")
build <- function(sense, A, relc, b, cc, lo, hi, kind) {
  n <- ncol(A); lpm <- make.lp(0, n)
  lp.control(lpm, sense = if (sense == 1) "max" else "min")
  set.objfn(lpm, cc)
  for (i in seq_len(nrow(A))) add.constraint(lpm, A[i, ], relstr[relc[i] + 1], b[i])
  set.bounds(lpm, lower = ifelse(lo <= -inf, -Inf, lo), upper = ifelse(hi >= inf, Inf, hi))
  for (j in seq_len(n)) if (kind[j] == 1) set.type(lpm, j, "integer") else if (kind[j] == 2) set.type(lpm, j, "binary")
  lpm
}
record <- function(sense, A, relc, b, cc, lo, hi, kind, lin = TRUE) {
  lpm <- build(sense, A, relc, b, cc, lo, hi, kind)
  st <- solve(lpm); a <- enc(sense, A, relc, b, cc, lo, hi, kind)
  add("status", a, st)
  if (st == 0) {
    add("obj", a, get.objective(lpm))
    if (lin) {
      add("x", a, sum(get.variables(lpm) * seq_len(ncol(A))))
      add("cons", a, sum(get.constraints(lpm) * seq_len(nrow(A))))
    }
  }
  st
}
set.seed(20262400)
cnt <- c(opt = 0, inf = 0, unb = 0)
for (rep in 1:400) {
  n <- sample(2:5, 1); me <- sample(0:1, 1); mi <- sample(2:5, 1)
  sense <- sample(0:1, 1)
  x0 <- round(runif(n, -2, 4), 2)
  cc <- round(runif(n, -2, 3), 2)
  lo <- sample(c(0, 0, -3, -Inf), n, TRUE); hi <- sample(c(Inf, Inf, 8, 12), n, TRUE)
  lo <- ifelse(lo > x0, x0 - 1, lo); hi <- ifelse(hi < x0, x0 + 1, hi)
  Ae <- matrix(round(runif(me * n, -1, 3), 2), me, n); Ai <- matrix(round(runif(mi * n, -1, 3), 2), mi, n)
  rl <- sample(0:1, mi, TRUE)
  bi <- as.vector(Ai %*% x0) + ifelse(rl == 0, 1, -1) * round(runif(mi, 0.5, 4), 2)
  A <- rbind(Ae, Ai, rep(1, n)); relc <- c(rep(2, me), rl, 0); b <- c(as.vector(Ae %*% x0), bi, sum(x0) + 6)
  st <- record(sense, A, relc, b, cc, lo, hi, rep(0, n))
  if (st == 0) cnt["opt"] <- cnt["opt"] + 1 else if (st == 2) cnt["inf"] <- cnt["inf"] + 1 else cnt["unb"] <- cnt["unb"] + 1
}
# infeasible by construction: sum x >= 10 and sum x <= 5
for (rep in 1:15) {
  n <- sample(2:4, 1); A <- rbind(matrix(round(runif(n, 0.5, 2), 2), 1, n), matrix(1, 1, n), matrix(1, 1, n))
  b <- c(round(runif(1, 5, 9), 1), 4, 11); relc <- c(0, 0, 1)
  record(sample(0:1, 1), A, relc, b, round(runif(n, 0, 3), 1), rep(0, n), rep(inf, n), rep(0, n))
}
# unbounded by construction: maximise with only a lower-limiting row
for (rep in 1:15) {
  n <- sample(2:4, 1); A <- matrix(round(runif(2 * n, 0.5, 2), 2), 2, n)
  record(1, A, c(1, 1), c(1, 2), round(runif(n, 0.5, 3), 1), rep(0, n), rep(inf, n), rep(0, n))
}
# integer and binary programs
skipped <- 0; kept <- 0
brute <- function(sense, A, relc, b, cc, lo, hi) {
  g <- as.matrix(expand.grid(lapply(seq_along(cc), function(j) lo[j]:hi[j])))
  act <- g %*% t(A); ok <- rep(TRUE, nrow(g))
  for (i in seq_len(nrow(A))) ok <- ok & (if (relc[i] == 0) act[, i] <= b[i] + 1e-9 else if (relc[i] == 1) act[, i] >= b[i] - 1e-9 else abs(act[, i] - b[i]) < 1e-9)
  if (!any(ok)) return(NA)
  v <- as.vector(g[ok, , drop = FALSE] %*% cc); if (sense == 1) max(v) else min(v)
}
for (rep in 1:600) {
  if (kept >= 90) break
  n <- sample(2:4, 1); m <- sample(2:4, 1); sense <- sample(0:1, 1)
  bin <- sample(c(TRUE, FALSE), 1)
  lo <- rep(0, n); hi <- if (bin) rep(1, n) else sample(3:6, n, TRUE)
  A <- matrix(sample(-2:5, m * n, TRUE), m, n); relc <- sample(0:2, m, TRUE, prob = c(.5, .35, .15))
  x0 <- sapply(seq_len(n), function(j) sample(lo[j]:hi[j], 1)); b <- as.vector(A %*% x0)
  b <- b + ifelse(relc == 0, sample(0:3, m, TRUE), ifelse(relc == 1, -sample(0:3, m, TRUE), 0))
  cc <- sample(-3:6, n, TRUE)
  want <- brute(sense, A, relc, b, cc, lo, hi)
  lpm <- build(sense, A, relc, b, cc, lo, hi, rep(if (bin) 2 else 1, n)); st <- solve(lpm)
  if (is.na(want)) { if (st == 2) { record(sense, A, relc, b, cc, lo, hi, rep(if (bin) 2 else 1, n), lin = FALSE); kept <- kept + 1 }; next }
  if (st != 0 || abs(get.objective(lpm) - want) > 1e-7) { skipped <- skipped + 1; next }
  record(sense, A, relc, b, cc, lo, hi, rep(if (bin) 2 else 1, n), lin = FALSE); kept <- kept + 1
}
cat("lpsolveapi: lp optimal", cnt["opt"], "infeasible", cnt["inf"], "unbounded", cnt["unb"], "; integer kept", kept, "skipped (lp_solve below the optimum)", skipped, "\n")
emit("lpsolveapi", "lpSolveAPI", list(cases))
