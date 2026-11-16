# nloptr BOBYQA (xtol_rel 1e-12) on a battery of smooth test functions inside a box.
#   args: (id, n, x0[n], lo[n], hi[n], j)   fn "val" (j ignored) and "x" (coordinate j)
#   ids: 0 Rosenbrock, 1 Beale, 2 Himmelblau, 3 Booth, 4 shifted bowl sum((x-i)^2*i)
suppressMessages(library(nloptr))
fs <- list(
  function(x) sum(100 * (x[-1] - x[-length(x)]^2)^2 + (1 - x[-length(x)])^2),
  function(x) (1.5 - x[1] + x[1] * x[2])^2 + (2.25 - x[1] + x[1] * x[2]^2)^2 + (2.625 - x[1] + x[1] * x[2]^3)^2,
  function(x) (x[1]^2 + x[2] - 11)^2 + (x[1] + x[2]^2 - 7)^2,
  function(x) (x[1] + 2 * x[2] - 7)^2 + (2 * x[1] + x[2] - 5)^2,
  function(x) sum((x - seq_along(x))^2 * seq_along(x)))
battery <- list(
  list(0, c(-1.2, 1), c(-5, -5), c(5, 5)), list(0, c(-1.2, 1), c(-5, -5), c(0.5, 5)),
  list(0, c(-1, 1, 1, 1), rep(-3, 4), rep(3, 4)), list(1, c(1, 1), c(-4.5, -4.5), c(4.5, 4.5)),
  list(1, c(2, 0.2), c(-4.5, -4.5), c(4.5, 4.5)), list(2, c(1, 1), c(-5, -5), c(5, 5)),
  list(2, c(-1, 1), c(-5, -5), c(5, 5)), list(2, c(-1, -1), c(-5, -5), c(5, 5)),
  list(3, c(0, 0), c(-10, -10), c(10, 10)), list(4, c(0, 0, 0), rep(-10, 3), c(1.5, 2.5, 2)),
  list(4, c(5, 5, 5, 5, 5), rep(-10, 5), rep(10, 5)))
cases <- list()
for (b in battery) {
  id <- b[[1]]; f <- fs[[id + 1]]; x0 <- b[[2]]; lo <- b[[3]]; hi <- b[[4]]; n <- length(x0)
  r <- nloptr(x0, f, lb = lo, ub = hi, opts = list(algorithm = "NLOPT_LN_BOBYQA", xtol_rel = 1e-12, ftol_rel = 1e-15, maxeval = 100000))
  a <- c(id, n, x0, lo, hi)
  cases[[length(cases) + 1]] <- case("val", c(a, 0), r$objective, rel = 0, abs = 1e-7)
  for (j in 1:n) cases[[length(cases) + 1]] <- case("x", c(a, j - 1), r$solution[j], rel = 0, abs = 1e-3)
}
emit("dfree", "nloptr", list(cases))
