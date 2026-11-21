# lpSolve: lp(compute.sens = 1) on integer and binary programs (int.vec, binary.vec, all.int, all.bin): the duals (m constraint prices then n reduced costs) of the final linear program, plus the objective value.
#   fn "si" args (n, m, maximise, c[n], A row-major [m * n], b[m], code[m] (0 <=, 1 >=, 2 =), kind[n] (0 real, 1 integer, 2 binary), field, index): field 0 duals[index] (1-based over m + n), 1 objval,
#   2 duals.from[index], 3 duals.to[index] (rows and continuous variables), 4 sens.coef.from[index], 5 sens.coef.to[index] (1-based over n)
#   Phase 0 has <= rows; phase 1 mixes <=, >= and = rows and also minimises over binary variables. The ranges are kept for programs whose integer variables are all nonbasic in lp_solve's last program (see rangesok).
#   Only programs where lpSolve reaches the true optimum are kept (it stops below it on about 5 percent of mixed problems).
suppressMessages(library(lpSolve))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("si", args, want, rel = 1e-9, abs = 1e-9)
set.seed(20262777)
dirs <- c("<=", ">=", "=")
trueopt <- function(mx, cc, A, dr, b, kind) {
  n <- length(cc); ints <- which(kind > 0)
  ub <- vapply(ints, function(j) if (kind[j] == 2) 1 else { r <- A[, j] > 0 & dr == "<="; if (any(r)) floor(min(b[r] / A[r, j]) + 1e-9) else 0 }, 0)
  grid <- as.matrix(expand.grid(lapply(ub, function(u) 0:u)))
  best <- if (mx) -Inf else Inf; cont <- setdiff(seq_len(n), ints)
  for (g in seq_len(nrow(grid))) {
    xi <- grid[g, ]; bb <- b - as.vector(A[, ints, drop = FALSE] %*% xi); base <- sum(cc[ints] * xi)
    if (length(cont) == 0) {
      ok <- all(ifelse(dr == "<=", bb >= -1e-9, ifelse(dr == ">=", bb <= 1e-9, abs(bb) < 1e-9)))
      if (ok) best <- if (mx) max(best, base) else min(best, base)
      next
    }
    sg <- lp(if (mx) "max" else "min", cc[cont], A[, cont, drop = FALSE], dr, bb)
    if (sg$status == 0) best <- if (mx) max(best, base + sg$objval) else min(best, base + sg$objval)
  }
  best
}
kept <- 0; skipped <- 0
for (phase in 0:1) for (rep in 1:500) {
  if (rep == 1) kept <- 0
  mixed <- phase == 1   # phase 1: a mix of <=, >= and = rows, and minimising over binary variables
  n <- sample(2:4, 1); m <- sample(2:4, 1); mx <- rep %% 2 == 0
  A <- matrix(round(runif(m * n, 0.5, 5), 1), m, n); cc <- round(runif(n, 0.5, 6), 1)
  style <- rep %% 6   # 0 all.int, 1 all.bin, else a mix of kinds
  kind <- if (style == 0) rep(1, n) else if (style == 1) rep(2, n) else sample(0:2, n, TRUE)
  if (all(kind == 0)) kind[1] <- 1
  # minimising over binary variables: lpSolve's reduced costs are not those of the maximisation reading and are not reproduced
  if (!mx && any(kind == 2) && !mixed) next
  x0 <- round(runif(n, 0, 3))
  dr <- rep("<=", m)
  b <- round(as.vector(A %*% x0) + runif(m, 0.5, 6), 1)
  if (style == 1) b <- round(runif(m, 2, 8), 1)
  if (!mx && !mixed) cc <- -cc
  if (mixed) {
    dr <- sample(dirs, m, TRUE, prob = c(0.45, 0.35, 0.2))
    b <- ifelse(dr == "<=", b, ifelse(dr == ">=", round(pmax(as.vector(A %*% x0) - runif(m, 0.5, 4), 0.5), 1), round(as.vector(A %*% x0), 1)))
  }
  r <- tryCatch(lp(if (mx) "max" else "min", cc, A, dr, b, all.int = style == 0, all.bin = style == 1,
                   int.vec = if (style >= 2) which(kind == 1), binary.vec = if (style >= 2) which(kind == 2), compute.sens = 1), error = function(e) NULL)
  if (is.null(r) || r$status != 0) next
  bo <- trueopt(mx, cc, A, dr, b, kind)
  if (abs(bo - r$objval) > 1e-7) { skipped <- skipped + 1; next }
  # a nondegenerate last program: as many binding rows as continuous variables in the basis (otherwise lp_solve completes the basis by a rule that is not reproduced)
  if (sum(abs(as.vector(A %*% r$solution) - b) < 1e-7) != sum(kind == 0 & r$solution > 1e-9)) { skipped <- skipped + 1; next }
  # an integer or binary variable that lp_solve left basic in its last program (reduced cost zero) is also left out
  if (any(r$duals[m + which(kind > 0)] == 0)) { skipped <- skipped + 1; next }
  kept <- kept + 1
  a <- c(n, m, as.numeric(mx), cc, as.vector(t(A)), b, match(dr, dirs) - 1, kind)
  add(c(a, 1, 1), r$objval)
  for (k in seq_len(m + n)) add(c(a, 0, k), r$duals[k])
  ii <- which(kind > 0); sg <- if (mx) 1 else -1
  rangesok <- !(!mx && any(kind == 2) && any(dr == "="))   # min over binary variables with an equality row: the ranges follow a basis choice of lp_solve that is not reproduced
  if (rangesok && all((r$solution[ii] == 0 & sg * r$duals[m + ii] <= 0) | (any(kind == 0) & r$solution[ii] > 0 & sg * r$duals[m + ii] > 0))) {  # ranges, when every integer variable is nonbasic: at zero with a non-improving cost, or held at a positive bound by an improving one
    # an integer variable's own value range depends on which bound lp_solve branched on last and is left out; rows and continuous variables are checked
    for (k in c(seq_len(m), m + which(kind == 0))) { add(c(a, 2, k), r$duals.from[k]); add(c(a, 3, k), r$duals.to[k]) }
    for (k in seq_len(n)) { add(c(a, 4, k), r$sens.coef.from[k]); add(c(a, 5, k), r$sens.coef.to[k]) }
  }
  if (kept >= 70) break
}
message("kept ", kept, " skipped ", skipped)
emit("lpsolve_sensint", "lpSolve", list(cases))
