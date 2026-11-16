# SQUAREM: squarem (no objective, methods 1 to 3) and fpiter on four fixed-point maps.
#   args: (map, method, tol, maxiter, n, par[n], kind)  kind 0 squarem 1 fpiter;   fn "par" (position last), "iter", "fpevals", "conv"
#   maps: 0 cos(x)   1 (0.5 cos(y) + 0.2, 0.3 sin(x) + 0.1 y)   2 Newton square roots (0.5 (x + c / x), c = 2, 5, 11)
#   3 (0.5 tanh(y) + 0.3, 0.4 tanh(x + z), 0.6 cos(x - y))
library(SQUAREM)
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
maps <- list(function(p) cos(p), function(p) c(0.5 * cos(p[2]) + 0.2, 0.3 * sin(p[1]) + 0.1 * p[2]),
             function(p) 0.5 * (p + c(2, 5, 11) / p), function(p) c(0.5 * tanh(p[2]) + 0.3, 0.4 * tanh(p[1] + p[3]), 0.6 * cos(p[1] - p[2])))
starts <- list(list(0.3, 2, -1), list(c(0, 0), c(1.5, -2), c(-3, 4)), list(c(1, 1, 1), c(5, 3, 8), c(0.5, 9, 2)), list(c(0, 0, 0), c(1, -1, 2), c(-2, 3, 0.5)))
for (mp in 0:3) for (st in starts[[mp + 1]]) {
  f <- maps[[mp + 1]]
  for (method in 1:3) for (tol in c(1e-7, 1e-10)) {
    r <- tryCatch(squarem(st, f, control = list(method = method, tol = tol, maxiter = 500)), error = function(e) NULL)
    if (is.null(r)) next
    a <- c(mp, method, tol, 500, length(st), st, 0)
    for (i in seq_along(r$par)) add("par", c(a, i - 1), r$par[i])
    add("iter", a, r$iter); add("fpevals", a, r$fpevals); add("conv", a, as.numeric(r$convergence))
  }
  fp <- fpiter(st, f, control = list(tol = 1e-8, maxiter = 400))
  a <- c(mp, 0, 1e-8, 400, length(st), st, 1)
  for (i in seq_along(fp$par)) add("par", c(a, i - 1), fp$par[i])
  add("fpevals", a, fp$fpevals); add("conv", a, as.numeric(fp$convergence))
}
emit("squarem", "SQUAREM", list(cases))
