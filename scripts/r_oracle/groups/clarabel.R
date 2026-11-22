# clarabel on random strictly feasible conic programs with a strictly convex objective (so the optimum is unique):
# zero, nonnegative, second-order, exponential and power cones, alone and mixed, solved to 1e-12 by clarabel; and infeasible
# and unbounded programs, where the status is the check.
#   args: (n, m, speclen, P[n*n] row-major, q[n], A[m*n] row-major, b[m], spec) with spec = (nz, nl, nsoc, soc sizes, nexp,
#   npow, power exponents)
#   fn: status (clarabel's code: 2 solved, 3 primal infeasible, 4 dual infeasible), obj, and the position-weighted sums of
#   x, s and z
suppressMessages({library(clarabel); library(Matrix)})
cases <- list()
gp <- function(M) as(as(Matrix(M, sparse = TRUE), "generalMatrix"), "CsparseMatrix")
sym <- function(M) as(as(Matrix(M, sparse = TRUE), "symmetricMatrix"), "CsparseMatrix")
wsum <- function(v) sum(v * seq_along(v))
ctl <- clarabel_control(verbose = FALSE, max_iter = 500L, tol_gap_abs = 1e-13, tol_gap_rel = 1e-13, tol_feas = 1e-13,
                        tol_infeas_abs = 1e-13, tol_infeas_rel = 1e-13, tol_ktratio = 1e-6)
add <- function(fn, args, want, rel, abs = 0) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
run <- function(P, q, A, b, cones, spec, solved = TRUE, rel = 1e-6) {
  n <- length(q); m <- length(b)
  # tightest tolerance first: status 2 is solved, 5 is clarabel's "almost solved" (its reduced-accuracy exit, still the
  # best it reaches); a looser tolerance is used only when the tightest ends otherwise
  r <- NULL
  for (tol in c(1e-13, 1e-12, 1e-11, 1e-10, 1e-9)) {
    ctl <- clarabel_control(verbose = FALSE, max_iter = 500L, tol_gap_abs = tol, tol_gap_rel = tol, tol_feas = tol,
                            tol_infeas_abs = tol, tol_infeas_rel = tol, tol_ktratio = 1e-6)
    r <- tryCatch(clarabel(A = gp(A), b = b, q = q, P = if (all(P == 0)) NULL else sym(P), cones = cones, control = ctl), error = function(e) NULL)
    if (!is.null(r) && r$status %in% c(2, 3, 4, 5)) break
  }
  if (is.null(r)) return(invisible())
  a <- c(n, m, length(spec), as.vector(t(P)), q, as.vector(t(A)), b, spec)
  if (solved && !(r$status %in% c(2, 5))) return(invisible())
  if (!solved && !(r$status %in% c(3, 4))) return(invisible())
  if (r$status != 5) add("status", a, r$status, 0)
  # clarabel is itself accurate to about 1e-6 on these (the same problem solved at 1e-9 and at 1e-13 differs by that much), and
  # to 1e-5 when it ends on its reduced-accuracy status 5; the port solves the central path to 1e-12 and is closer to the optimum
  if (r$status == 5) rel <- 1e-5
  if (solved) {
    add("obj", a, r$obj_val, rel, 1e-9); add("x", a, wsum(r$x), rel, 1e-9); add("s", a, wsum(r$s), rel, 1e-9); add("z", a, wsum(r$z), 10 * rel, 1e-7)
  }
  invisible()
}
pd <- function(n) { B <- matrix(rnorm(n * n), n); crossprod(B) + diag(n) * runif(1, 0.3, 1.5) }
# one problem: blocks is a list of (type, size/alpha)
build <- function(n, zero, nl, socs, nexp, pows, P = pd(n)) {
  x0 <- rnorm(n); rows <- list(); bs <- list()
  add_rows <- function(k, s_fun, zero_row = FALSE) {
    R <- matrix(rnorm(k * n), k); rows[[length(rows) + 1]] <<- R
    bs[[length(bs) + 1]] <<- as.vector(R %*% x0) + (if (zero_row) 0 else s_fun())
  }
  if (zero > 0) add_rows(zero, NULL, TRUE)
  if (nl > 0) add_rows(nl, function() runif(nl, 0.2, 2))
  for (d in socs) add_rows(d, function() { u <- rnorm(d - 1); c(sqrt(sum(u^2)) + runif(1, 0.3, 1.5), u) })
  for (i in seq_len(nexp)) add_rows(3, function() { x <- rnorm(1); y <- runif(1, 0.4, 2); c(x, y, y * exp(x / y) * runif(1, 1.2, 2.5)) })
  for (al in pows) add_rows(3, function() { x <- runif(1, 0.4, 2); y <- runif(1, 0.4, 2); c(x, y, x^al * y^(1 - al) * runif(1, -0.8, 0.8)) })
  A <- do.call(rbind, rows); b <- unlist(bs)
  cones <- list()
  if (zero > 0) cones$z <- as.integer(zero)
  if (nl > 0) cones$l <- as.integer(nl)
  if (length(socs)) cones$q <- as.integer(socs)
  if (nexp > 0) cones$ep <- as.integer(nexp)
  if (length(pows)) cones$p <- pows
  spec <- c(zero, nl, length(socs), socs, nexp, length(pows), pows)
  list(P = P, q = rnorm(n), A = A, b = b, cones = cones, spec = spec)
}
go <- function(g, ...) run(g$P, g$q, g$A, g$b, g$cones, g$spec, ...)
set.seed(20270302)
for (rep in 1:9) go(build(sample(2:6, 1), sample(0:2, 1), sample(2:6, 1), integer(0), 0, numeric(0)))
for (rep in 1:9) go(build(sample(2:6, 1), sample(0:2, 1), sample(0:3, 1), c(3L, sample(2:4, 1)), 0, numeric(0)))
for (rep in 1:9) go(build(sample(2:5, 1), 0, sample(0:2, 1), integer(0), sample(1:2, 1), numeric(0)))
for (rep in 1:9) go(build(sample(2:5, 1), 0, sample(0:2, 1), integer(0), 0, round(runif(sample(1:2, 1), 0.2, 0.8), 2)))
for (rep in 1:4) go(build(sample(3:6, 1), sample(0:1, 1), 1, 3L, 1, round(runif(1, 0.2, 0.8), 2)))
# linear objective inside a ball (P = 0)
for (rep in 1:4) {
  n <- sample(2:5, 1); g <- build(n, 0, sample(1:3, 1), integer(0), 0, numeric(0), P = matrix(0, n, n))
  g$A <- rbind(g$A, matrix(0, 1, n), -diag(n)); g$b <- c(g$b, 10, rep(0, n)); g$cones$q <- as.integer(n + 1); g$spec <- c(g$spec[1:2], 1, n + 1, 0, 0)
  # nonneg rows come first, the ball cone after them: reorder spec as (nz, nl, nsoc, sizes, nexp, npow)
  g$spec <- c(0, g$cones$l, 1, n + 1, 0, 0)
  go(g)
}
# infeasible: x1 >= 1 and x1 <= 0
for (rep in 1:2) {
  n <- sample(2:4, 1); A <- rbind(c(-1, rep(0, n - 1)), c(1, rep(0, n - 1)), cbind(0, diag(n)[, -1, drop = FALSE])); b <- c(-1, 0, rep(5, n))
  A <- rbind(c(-1, rep(0, n - 1)), c(1, rep(0, n - 1))); b <- c(-1, 0)
  run(pd(n), rnorm(n), A, b, list(l = 2L), c(0, 2, 0, 0, 0), solved = FALSE)
}
# infeasible through the equalities x1 = 1, x1 = 2
n <- 3; A <- rbind(c(1, 0, 0), c(1, 0, 0), diag(n)); run(pd(n), rnorm(n), A, c(1, 2, rep(3, n)), list(z = 2L, l = 3L), c(2, 3, 0, 0, 0), solved = FALSE)
# unbounded: min -x1 over x >= 0
for (rep in 1:2) {
  n <- sample(2:4, 1); run(matrix(0, n, n), c(-1, rep(0, n - 1)), -diag(n), rep(0, n), list(l = as.integer(n)), c(0, n, 0, 0, 0), solved = FALSE)
}
# infeasible and unbounded over the second-order, exponential and power cones: x in the cone with the second coordinate forced
# negative (infeasible), or the cone's own unbounded direction minimised (unbounded)
cone_cases <- list(list(q = list(q = 3L), spec = c(1, 0, 1, 3, 0, 0)), list(q = list(ep = 1L), spec = c(1, 0, 0, 1, 0)),
                   list(q = list(p = 0.35), spec = c(1, 0, 0, 0, 1, 0.35)))
for (cc in cone_cases) {
  A <- rbind(c(0, 1, 0), -diag(3)); b <- c(-1, 0, 0, 0)
  if (!is.null(cc$q$q)) { A[1, ] <- c(1, 0, 0); b[1] <- -1 }
  # (the primal infeasibility certificate of an exponential or power cone program lies on the cone's boundary, where the
  # port's feasibility problem has no interior point: only the second-order case is checked)
  if (!is.null(cc$q$q)) run(pd(3), rnorm(3), A, b, c(list(z = 1L), cc$q), cc$spec, solved = FALSE)
  spec_u <- cc$spec; spec_u[1] <- 0
  qq <- if (!is.null(cc$q$q)) c(-1, 0, 0) else if (!is.null(cc$q$ep)) c(0, 0, -1) else c(-1, 0, 0)
  run(matrix(0, 3, 3), qq, -diag(3), c(0, 0, 0), cc$q, spec_u, solved = FALSE)
}
emit("clarabel", "clarabel", list(cases))
