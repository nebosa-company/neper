# nloptr COBYLA with equality and inequality constraints on three small problems.
#   args: (id, n, x0[n], lo[n], hi[n], j)   fn "val" and "x" (coordinate j)
#   ids: 0 HS071, 1 ellipse with a line, 2 sum of squares on a line
suppressMessages(library(nloptr))
P <- list(
  list(f = function(x) x[1] * x[4] * (x[1] + x[2] + x[3]) + x[3], gi = function(x) 25 - x[1] * x[2] * x[3] * x[4], ge = function(x) sum(x^2) - 40),
  list(f = function(x) (x[1] - 2)^2 + (x[2] - 1)^2, gi = function(x) x[1]^2 / 4 + x[2]^2 - 1, ge = function(x) x[1] - 2 * x[2] + 1),
  list(f = function(x) sum(x^2), gi = function(x) -1, ge = function(x) sum(x) - 1))
battery <- list(list(0, c(1, 5, 5, 1), rep(1, 4), rep(5, 4)), list(1, c(0, 0), c(-5, -5), c(5, 5)), list(2, c(3, -2), c(-5, -5), c(5, 5)))
cases <- list()
for (b in battery) {
  p <- P[[b[[1]] + 1]]; x0 <- b[[2]]; lo <- b[[3]]; hi <- b[[4]]; n <- length(x0)
  r <- nloptr(x0, p$f, lb = lo, ub = hi, eval_g_ineq = p$gi, eval_g_eq = p$ge,
              opts = list(algorithm = "NLOPT_LN_COBYLA", xtol_rel = 1e-11, ftol_rel = 1e-14, maxeval = 200000))
  a <- c(b[[1]], n, x0, lo, hi)
  cases[[length(cases) + 1]] <- case("val", c(a, 0), r$objective, rel = 0, abs = 1e-4)
  for (j in 1:n) cases[[length(cases) + 1]] <- case("x", c(a, j - 1), r$solution[j], rel = 0, abs = 1e-3)
}
emit("auglag", "nloptr", list(cases))
