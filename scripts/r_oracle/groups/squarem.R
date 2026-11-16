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
#   kinds 2 (squarem1: method 1..3 with the objective sum((p - F(p))^2)), 3 (cyclem1 with the objective) and 4 (cyclem2): the args continue
#   (..., kind, K, rre, square); fn "objf" is objfevals and "value" is value.objfn
for (mp in 0:3) for (st in starts[[mp + 1]]) {
  f <- maps[[mp + 1]]; of <- function(p) sum((p - f(p))^2); n <- length(st)
  for (method in 1:3) {
    r <- tryCatch(squarem(st, f, of, control = list(method = method, tol = 1e-9, maxiter = 500)), error = function(e) NULL)
    if (is.null(r)) next
    a <- c(mp, method, 1e-9, 500, n, st, 2, 1, 1, 1)
    for (i in seq_along(r$par)) add("par", c(a, i - 1), r$par[i])
    add("iter", a, r$iter); add("fpevals", a, r$fpevals); add("objf", a, r$objfevals); add("value", a, r$value.objfn); add("conv", a, as.numeric(r$convergence))
  }
  for (K in 2:3) if (K <= n) for (mt in c("rre", "mpe")) for (sqr in c(TRUE, FALSE)) for (hasobj in c(TRUE, FALSE)) {
    if (mt == "rre" && K + 1 > n) next  # crossprod(U) is singular: R solves it from rounding noise
    ctl <- list(K = K, method = mt, tol = 1e-9, maxiter = 500, square = sqr)
    r <- tryCatch(if (hasobj) squarem(st, f, of, control = ctl) else squarem(st, f, control = ctl), error = function(e) NULL)
    if (is.null(r)) next
    a <- c(mp, 0, 1e-9, 500, n, st, if (hasobj) 3 else 4, K, as.numeric(mt == "rre"), as.numeric(sqr))
    for (i in seq_along(r$par)) add("par", c(a, i - 1), r$par[i])
    add("iter", a, r$iter); add("fpevals", a, r$fpevals); add("conv", a, as.numeric(r$convergence))
    if (hasobj) { add("objf", a, r$objfevals); add("value", a, r$value.objfn) }
  }
}
emit("squarem", "SQUAREM", list(cases))
