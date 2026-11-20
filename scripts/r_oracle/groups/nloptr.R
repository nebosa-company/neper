# nloptr gradient-based and constrained optimizers against the ported NLopt algorithms.
#   args: (algo, prob, what)   what: 0 value, 1 status code, 2 evaluation count, 3 + j coordinate j
#   problems are defined in the fixture too (tests/selfhost/fixtures/link/oracle_nloptr/src/main.e)
suppressMessages(library(nloptr))
inf <- Inf
cube <- function(t) t * t * t
quart <- function(t) { s <- t * t; s * s }
P <- list(
  # 0 NLopt tutorial: min sqrt(x2) s.t. (2 x1)^3 <= x2, (1 - x1)^3 <= x2
  list(x0 = c(1.234, 5.678), lb = c(-inf, 0), ub = c(inf, inf),
       f = function(x) list(objective = sqrt(x[2]), gradient = c(0, 0.5 / sqrt(x[2]))),
       gi = function(x) list(constraints = c(cube(2 * x[1]) - x[2], cube(1 - x[1]) - x[2]),
                             jacobian = rbind(c( 3 * (2 * x[1])^2 * 2, -1), c(-3 * (1 - x[1])^2, -1)))),
  # 1 distance to a point inside an ellipse
  list(x0 = c(0, 0), lb = c(-5, -5), ub = c(5, 5),
       f = function(x) list(objective = (x[1] - 2)^2 + (x[2] - 1)^2, gradient = c(2 * (x[1] - 2), 2 * (x[2] - 1))),
       gi = function(x) list(constraints = x[1]^2 / 4 + x[2]^2 - 1, jacobian = rbind(c(x[1] / 2, 2 * x[2])))),
  # 2 three variables, a plane and a cylinder
  list(x0 = c(0, 0, 0), lb = rep(-5, 3), ub = rep(5, 3),
       f = function(x) list(objective = (x[1] - 1)^2 + (x[2] - 2)^2 + (x[3] - 3)^2, gradient = c(2 * (x[1] - 1), 2 * (x[2] - 2), 2 * (x[3] - 3))),
       gi = function(x) list(constraints = c(x[1] + x[2] + x[3] - 4, x[1]^2 + x[2]^2 - 2),
                             jacobian = rbind(c(1, 1, 1), c(2 * x[1], 2 * x[2], 0)))),
  # 3 Rosenbrock in a box
  list(x0 = c(-1.2, 1), lb = c(-2, -2), ub = c(2, 2),
       f = function(x) list(objective = 100 * (x[2] - x[1]^2)^2 + (1 - x[1])^2,
                            gradient = c(-400 * x[1] * (x[2] - x[1]^2) - 2 * (1 - x[1]), 200 * (x[2] - x[1]^2))),
       gi = NULL),
  # 4 infeasible start: min x1 + x2 s.t. x1 x2 >= 1
  list(x0 = c(0.2, 0.2), lb = c(0.1, 0.1), ub = c(10, 10),
       f = function(x) list(objective = x[1] + x[2], gradient = c(1, 1)),
       gi = function(x) list(constraints = 1 - x[1] * x[2], jacobian = rbind(c(-x[2], -x[1])))),
  # 5 HS071: one inequality and one equality
  list(x0 = c(1, 5, 5, 1), lb = rep(1, 4), ub = rep(5, 4),
       f = function(x) list(objective = x[1] * x[4] * (x[1] + x[2] + x[3]) + x[3],
                            gradient = c(x[1] * x[4] + x[4] * (x[1] + x[2] + x[3]), x[1] * x[4], x[1] * x[4] + 1, x[1] * (x[1] + x[2] + x[3]))),
       gi = function(x) list(constraints = 25 - x[1] * x[2] * x[3] * x[4],
                             jacobian = rbind(c(-x[2] * x[3] * x[4], -x[1] * x[3] * x[4], -x[1] * x[2] * x[4], -x[1] * x[2] * x[3]))),
       ge = function(x) list(constraints = x[1]^2 + x[2]^2 + x[3]^2 + x[4]^2 - 40, jacobian = rbind(c(2 * x[1], 2 * x[2], 2 * x[3], 2 * x[4])))),
  # 6 ellipse distance with a line
  list(x0 = c(0, 0), lb = c(-5, -5), ub = c(5, 5),
       f = function(x) list(objective = (x[1] - 2)^2 + (x[2] - 1)^2, gradient = c(2 * (x[1] - 2), 2 * (x[2] - 1))),
       gi = function(x) list(constraints = x[1]^2 / 4 + x[2]^2 - 1, jacobian = rbind(c(x[1] / 2, 2 * x[2]))),
       ge = function(x) list(constraints = x[1] - 2 * x[2] + 1, jacobian = rbind(c(1, -2)))),
  # 7 convex quadratic with two equalities and no inequality
  list(x0 = c(2, -1, 3), lb = rep(-10, 3), ub = rep(10, 3),
       f = function(x) list(objective = x[1]^2 + 2 * x[2]^2 + 3 * x[3]^2 + x[1] * x[2], gradient = c(2 * x[1] + x[2], 4 * x[2] + x[1], 6 * x[3])),
       gi = NULL,
       ge = function(x) list(constraints = c(x[1] + x[2] + x[3] - 1, x[1] - x[3]), jacobian = rbind(c(1, 1, 1), c(1, 0, -1)))),
  # 8 unconstrained quartic, no bounds
  list(x0 = c(3, -2, 1), lb = rep(-inf, 3), ub = rep(inf, 3),
       f = function(x) list(objective = quart(x[1] - 1) + quart(x[2] - 2) + quart(x[3] - 3) + x[1]^2 + x[2]^2 + x[3]^2, gradient = c(4 * cube(x[1] - 1) + 2 * x[1], 4 * cube(x[2] - 2) + 2 * x[2], 4 * cube(x[3] - 3) + 2 * x[3])),
       gi = NULL),
  # 9 bound-constrained quadratic with active bounds
  list(x0 = c(0, 0, 0), lb = rep(-1, 3), ub = rep(2, 3),
       f = function(x) list(objective = (x[1] - 3)^2 + 2 * (x[2] + 1)^2 + 3 * (x[3] - 0.5)^2 + 0.5 * x[1] * x[2],
                            gradient = c(2 * (x[1] - 3) + 0.5 * x[2], 4 * (x[2] + 1) + 0.5 * x[1], 6 * (x[3] - 0.5))),
       gi = NULL),
  # 10 six-variable Rosenbrock chain
  list(x0 = c(-1.2, 1, -1.2, 1, -1.2, 1), lb = rep(-inf, 6), ub = rep(inf, 6),
       f = function(x) { s <- 0; for (i in 1:5) { t <- x[i + 1] - x[i]^2; s <- s + (100 * (t * t) + (1 - x[i])^2) }; list(objective = s, gradient = chaing(x)) },
       gi = NULL)
)
chaing <- function(x) {
  g <- numeric(6)
  for (i in 1:5) { t <- x[i + 1] - x[i]^2; g[i] <- g[i] + (-400 * x[i] * t - 2 * (1 - x[i])); g[i + 1] <- g[i + 1] + 200 * t }
  g
}
ALG <- c("NLOPT_LD_MMA", "NLOPT_LD_CCSAQ", "NLOPT_LD_LBFGS", "NLOPT_LD_VAR1", "NLOPT_LD_VAR2", "NLOPT_LD_TNEWTON", "NLOPT_LD_TNEWTON_RESTART", "NLOPT_LD_TNEWTON_PRECOND", "NLOPT_LD_TNEWTON_PRECOND_RESTART", "NLOPT_LD_SLSQP")
# which problems each algorithm accepts: ineq only (MMA/CCSAQ), eq too (SLSQP, AUGLAG)
ACC <- list(c(0, 1, 2, 3, 4, 8, 9), c(0, 1, 2, 3, 4, 8, 9), c(3, 8, 9, 10), c(3, 8, 9, 10), c(3, 8, 9, 10), c(3, 8, 9, 10), c(3, 8, 9, 10), c(3, 8, 9, 10), c(3, 8, 9, 10), 0:10)
algspec <- function(a) {
  if (a < 20) return(list(alg = ALG[a + 1], local = NULL))
  loc <- a %% 20
  list(alg = if (a >= 40) "NLOPT_LD_AUGLAG_EQ" else "NLOPT_LD_AUGLAG", local = ALG[loc + 1])
}
run <- function(a0, p) {
  a <- a0 %% 1000
  variant <- a0 %/% 1000
  pr <- P[[p + 1]]
  sp <- algspec(a)
  opts <- list(algorithm = sp$alg, xtol_rel = 1e-10, ftol_rel = 1e-13, maxeval = 200, vector_storage = 20)
  if (a >= 20) {
    opts$maxeval <- 2000
    opts$local_opts <- list(algorithm = sp$local, xtol_rel = 1e-10, ftol_rel = 1e-13, maxeval = 300, vector_storage = 20)
  }
  if (variant == 1) opts$maxeval <- 7
  if (variant == 2) opts$stopval <- 1.5
  args <- list(x0 = pr$x0, eval_f = function(x) pr$f(x), lb = pr$lb, ub = pr$ub, opts = opts)
  if (!is.null(pr$gi)) { args$eval_g_ineq <- function(x) pr$gi(x) }
  if (!is.null(pr$ge)) { args$eval_g_eq <- function(x) pr$ge(x) }
  suppressMessages(do.call(nloptr, args))
}
cases <- list()
AL <- c(22, 20, 23, 25, 40, 29, 49, 41)
ACCAL <- c(0, 1, 2, 4, 5, 6, 7)
for (a in c(seq_along(ALG) - 1, AL)) for (p in if (a < 20) ACC[[a + 1]] else ACCAL) {
  r <- run(a, p)
  cases[[length(cases) + 1]] <- case("val", c(a, p, 0), r$objective, rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("status", c(a, p, 1), r$status, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("iter", c(a, p, 2), r$iterations, rel = 0, abs = 0)
  for (j in seq_along(r$solution)) cases[[length(cases) + 1]] <- case("x", c(a, p, 2 + j), r$solution[j], rel = 1e-9, abs = 1e-12)
}
# check.derivatives: id 0 correct scalar, 1 wrong scalar gradient, 2 wrong Jacobian of a 2-vector, 3 zeros point
f1 <- function(x) x[1] * x[2] + x[3] * x[3] * x[3] + (x[4] * x[4]) * x[1]
g1 <- function(x) c(x[2] + x[4] * x[4], x[1], 3 * (x[3] * x[3]), 2 * x[4] * x[1])
g1w <- function(x) g1(x) + c(0, 0.1, 0, 0)
v2 <- function(x) c(x[1] + x[2] * x[3], x[4] * x[4] + x[1] * x[3])
j2w <- function(x) rbind(c(1 + 0.01, x[3], x[2], 0), c(x[3], 0, x[1], 2 * x[4] + 0.5))
CK <- list(list(f1, g1, c(1.5, -2, 0.7, 3)), list(f1, g1w, c(1.5, -2, 0.7, 3)), list(v2, j2w, c(1.5, -2, 0.7, 3)), list(f1, g1, c(0, 1, -1, 0.5)))
for (id in 0:3) {
  ck <- CK[[id + 1]]
  r <- suppressMessages(check.derivatives(ck[[3]], ck[[1]], ck[[2]], check_derivatives_tol = 1e-4, check_derivatives_print = "none"))
  rel <- if (is.matrix(r$relative_error)) t(r$relative_error) else r$relative_error
  fdm <- if (is.matrix(r$finite_difference)) t(r$finite_difference) else r$finite_difference
  cases[[length(cases) + 1]] <- case("chk", c(100, id, 0), sum(r$flag_derivative_warning), rel = 0, abs = 0)
  for (k in seq_along(rel)) {
    cases[[length(cases) + 1]] <- case("chk", c(100, id, 1 + k - 1), as.numeric(rel)[k], rel = 1e-9, abs = 1e-12)
    cases[[length(cases) + 1]] <- case("chkfd", c(100, id, 100 + k - 1), as.numeric(fdm)[k], rel = 1e-9, abs = 1e-12)
  }
}
# option variants: 1000 + algo stops at maxeval 7, 2000 + algo at stopval 1.5
for (v in list(list(1000, c(0, 1, 2, 3, 4, 5, 6, 7, 8, 9), c(1, 3, 10)), list(2000, c(0, 1, 2, 3, 5, 9), c(1, 3, 10)))) {
  for (a in v[[2]]) for (p in v[[3]]) {
    if (a <= 1 && p %in% c(10)) next
    if (a >= 2 && a <= 8 && p == 1) next
    r <- run(v[[1]] + a, p)
    cases[[length(cases) + 1]] <- case("val", c(v[[1]] + a, p, 0), r$objective, rel = 1e-9, abs = 1e-12)
    cases[[length(cases) + 1]] <- case("status", c(v[[1]] + a, p, 1), r$status, rel = 0, abs = 0)
    cases[[length(cases) + 1]] <- case("iter", c(v[[1]] + a, p, 2), r$iterations, rel = 0, abs = 0)
    for (j in seq_along(r$solution)) cases[[length(cases) + 1]] <- case("x", c(v[[1]] + a, p, 2 + j), r$solution[j], rel = 1e-9, abs = 1e-12)
  }
}
emit("nloptr", "nloptr", list(cases))
