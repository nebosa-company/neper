# numDeriv: grad, jacobian, hessian and genD. A case is (op, func, method, element, point...) and
# answers one element of the flattened result, row-major. op 0 grad, 1 jacobian, 2 hessian,
# 3 genD. The functions are written so Neper evaluates the same operations in the same order
# (x*x*x, not x^3), and each also accepts a complex argument for the complex-step methods.
library(numDeriv)

funcs <- list(
  function(x) sin(x[1]),                                              # 1: n=1, m=1
  function(x) exp(x[1]) + x[1] * (x[2] * x[2]),                       # 2: n=2, m=1
  function(x) 100 * ((x[2] - x[1] * x[1]) * (x[2] - x[1] * x[1])) +
              (1 - x[1]) * (1 - x[1]),                                # 3: Rosenbrock
  function(x) x[1] * x[2] * x[3] + x[1] * x[1] * x[1],                # 4: n=3, m=1
  function(x) x[1] * x[1] + x[2] * x[2] + x[3] * x[3] + x[4] * x[4],  # 5: n=4, m=1
  function(x) c(x[1] * x[1] + x[2], sin(x[1]) * x[2]),                # 6: n=2, m=2
  function(x) x * x * x - 2 * x                                       # 7: n=3, m=3 elementwise
)
points <- list(
  list(0.7, 0, -2.3, 100),
  list(c(0.5, -1.2), c(0, 0), c(2, 3)),
  list(c(-1.2, 1), c(1, 1), c(0, 0)),
  list(c(1, 2, 3), c(0.3, -0.7, 2)),
  list(c(0, 0, 0, 0), c(1, -2, 0.5, 3)),
  list(c(0.5, 1.5), c(0, 0)),
  list(c(1, 2, -1), c(0.5, 0, 3))
)
mixed_side <- c(1, -1, NA, 1)

# method id -> (method, method.args, side kind): 0 none, 1 forward everywhere, 2 mixed
methods <- list(
  list("Richardson", list(), 0), list("Richardson", list(d = 0.01, r = 3), 0),
  list("Richardson", list(r = 5, eps = 1e-3), 0), list("simple", list(), 0),
  list("simple", list(eps = 1e-6), 0), list("complex", list(), 0),
  list("Richardson", list(), 1), list("Richardson", list(), 2), list("simple", list(), 2))
hessians <- list(list("Richardson", list()), list("Richardson", list(d = 0.05, r = 5)),
                 list("complex", list()), list("complex", list(d = 0.2, r = 3)))

side_of <- function(kind, n) switch(kind + 1, NULL, rep(1, n), mixed_side[seq_len(n)])

flat <- function(op, func, point, method, m) {
  if (op == 0) return(as.vector(grad(func, point, method = method[[1]], side = side_of(method[[3]], length(point)),
                                     method.args = method[[2]])))
  if (op == 1) return(as.vector(t(jacobian(func, point, method = method[[1]], side = side_of(method[[3]], length(point)),
                                           method.args = method[[2]]))))
  if (op == 2) return(as.vector(t(hessian(func, point, method = method[[1]], method.args = method[[2]]))))
  as.vector(t(genD(func, point, method.args = method[[2]])$D))
}

cases <- list()
add <- function(op, fi, pi, mi, method) {
  p <- points[[fi]][[pi]]
  m <- length(funcs[[fi]](p))
  vals <- suppressWarnings(tryCatch(flat(op, funcs[[fi]], p, method, m), error = function(e) NULL))
  if (is.null(vals)) return()
  for (e in seq_along(vals))
    cases[[length(cases) + 1]] <<- case("numderiv", c(op, fi, mi, e - 1, p), vals[e], rel = 1e-10, abs = 1e-12)
}

for (fi in seq_along(funcs)) for (pi in seq_along(points[[fi]])) {
  for (mi in seq_along(methods)) {
    me <- methods[[mi]]
    n <- length(points[[fi]][[pi]])
    if (me[[1]] == "complex" || me[[3]] == 0 || TRUE) {
      add(1, fi, pi, mi - 1, me)                                    # jacobian: every function
      if (fi != 6) add(0, fi, pi, mi - 1, me)                       # grad: scalar or elementwise
    }
  }
  if (fi %in% 1:5) for (hi in seq_along(hessians)) add(2, fi, pi, hi - 1, list(hessians[[hi]][[1]], hessians[[hi]][[2]], 0))
  if (fi %in% c(2, 3, 4, 6)) add(3, fi, pi, 0, list("Richardson", list(d = 0.1), 0))
  if (fi %in% c(2, 6)) add(3, fi, pi, 1, list("Richardson", list(d = 0.02, r = 3), 0))
}
emit("numderiv", "numDeriv", list(cases))
