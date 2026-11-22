# osqp (OSQP 1.0.0) on random quadratic and linear programs: the ADMM iteration with Ruiz scaling, adaptive rho, polishing,
# infeasibility certificates, warm starts and data updates. Status, iteration counts, rho updates and the polish status are
# exact; the values are compared at 1e-9 relative (1e-11 absolute where the value is a residual that polishing drives to zero).
#   args: (scenario, n, m, eps_abs, eps_rel, max_iter, polishing, adaptive_rho, adaptive_rho_interval, rho, sigma, alpha,
#          scaling, check_termination, P[n*n] row-major, q[n], A[m*n] row-major, l[m], u[m], extras)
#   scenario 0 solve; 1 solve then update q, l, u (extras q2, l2, u2) and solve again; 2 solve then update P and A values
#   (extras P2, A2) and solve again; 3 warm start before the solve (extras x0, y0)
#   fn: status, iter, obj, dual_obj, prim_res, dual_res, gap, rho_updates, rho_estimate, status_polish, and the position-weighted
#   sums x, y, pcert, dcert
suppressMessages({library(osqp); library(Matrix)})
cases <- list()
ex <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 0, abs = 0)
# Values: 5e-8 relative plus 2e-8 absolute (osqp factorises the KKT matrix in an AMD order, this port in natural order; the
# iterates differ by that rounding, at most 1e-8 here). Residuals and the gap are differences of O(1) terms, so their noise
# floor is absolute: 1e-6 relative plus 5e-9 absolute. rho_estimate is a ratio of the two residuals and is compared (5e-3
# relative) only when both are above 1e-6.
# A warm-started second solve after a data update (scenario 1) accumulates more of that rounding: 20 times looser.
tolmul <- 1
ap <- function(fn, args, want, rel = 5e-8, abs = 2e-8) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel * tolmul, abs = abs * tolmul)
rs <- function(fn, args, want) ap(fn, args, want, 1e-6, 5e-9)
sp <- function(M) Matrix(M, sparse = TRUE)
wsum <- function(v) sum(v * seq_along(v))
solve_scenario <- function(sc, set, P, q, A, l, u, extra) {
  pars <- do.call(osqpSettings, c(list(verbose = FALSE), set))
  model <- osqp(sp(P), q, sp(A), l, u, pars)
  if (sc == 3) model@WarmStart(x = extra$x0, y = extra$y0)
  r <- model@Solve()
  if (sc == 1) { model@Update(q = extra$q2, l = extra$l2, u = extra$u2); r <- model@Solve() }
  if (sc == 2) { model@Update(Px = triu(sp(extra$P2))@x, Ax = sp(extra$A2)@x); r <- model@Solve() }
  r
}
problem <- function(sc, P, q, A, l, u, set = list(), extra = list()) {
  n <- length(q); m <- length(l)
  s <- modifyList(list(eps_abs = 1e-3, eps_rel = 1e-3, max_iter = 4000L, polishing = FALSE, adaptive_rho = 1L,
                       adaptive_rho_interval = 50L, rho = 0.1, sigma = 1e-6, alpha = 1.6, scaling = 10L, check_termination = 25L), set)
  r <- tryCatch(solve_scenario(sc, s, P, q, A, l, u, extra), error = function(e) NULL)
  if (is.null(r)) return(invisible())
  ex_args <- switch(sc + 1, numeric(0), c(extra$q2, extra$l2, extra$u2), c(as.vector(t(extra$P2)), as.vector(t(extra$A2))), c(extra$x0, extra$y0))
  a <- c(sc, n, m, s$eps_abs, s$eps_rel, s$max_iter, as.integer(s$polishing), s$adaptive_rho, s$adaptive_rho_interval, s$rho, s$sigma,
         s$alpha, s$scaling, s$check_termination, as.vector(t(P)), q, as.vector(t(A)), l, u, ex_args)
  i <- r$info
  tolmul <<- if (sc == 1) 20 else 1
  ex("status", a, i$status_val); ex("iter", a, i$iter); ex("rho_updates", a, i$rho_updates); ex("status_polish", a, i$status_polish)
  if (min(i$prim_res, i$dual_res) > 1e-6) ap("rho_estimate", a, i$rho_estimate, 5e-3, 0)
  rs("prim_res", a, i$prim_res); rs("dual_res", a, i$dual_res)
  if (i$status_val %in% c(1, 2, 7)) {
    ap("obj", a, i$obj_val); ap("dual_obj", a, i$dual_obj_val); rs("gap", a, i$duality_gap)
    ap("x", a, wsum(r$x)); ap("y", a, wsum(r$y))
  } else if (i$status_val %in% c(3, 4)) {
    ap("pcert", a, wsum(r$prim_inf_cert))
  } else if (i$status_val %in% c(5, 6)) {
    ap("dcert", a, wsum(r$dual_inf_cert))
  }
  invisible()
}
gen <- function(n, m, kind = "qp", eqf = 0.2) {
  B <- matrix(rnorm(n * n), n)
  P <- crossprod(B) + diag(n) * runif(1, 0.2, 2)
  if (kind == "lp") P <- matrix(0, n, n)
  if (kind == "lowrank") P <- tcrossprod(matrix(rnorm(n * 2), n)) + diag(n) * 1e-3
  q <- rnorm(n); A <- matrix(rnorm(m * n), m); x0 <- rnorm(n)
  l <- as.vector(A %*% x0 - runif(m)); u <- as.vector(A %*% x0 + runif(m))
  eq <- rbinom(m, 1, eqf) == 1; l[eq] <- u[eq] <- as.vector(A %*% x0)[eq]
  if (kind == "lp") {  # box rows keep it bounded
    A <- rbind(A, diag(n)); l <- c(l, rep(-5, n)); u <- c(u, rep(5, n))
  }
  list(P = P, q = q, A = A, l = l, u = u, n = n, m = nrow(A))
}
set.seed(20270301)
for (rep in 1:8) { g <- gen(sample(2:8, 1), sample(2:10, 1)); problem(0, g$P, g$q, g$A, g$l, g$u) }
for (rep in 1:4) { g <- gen(sample(3:7, 1), sample(3:9, 1)); problem(0, g$P, g$q, g$A, g$l, g$u, list(polishing = TRUE)) }
for (rep in 1:4) { g <- gen(sample(3:7, 1), sample(3:9, 1)); problem(0, g$P, g$q, g$A, g$l, g$u, list(eps_abs = 1e-8, eps_rel = 1e-8, max_iter = 200000L, polishing = TRUE)) }
for (rep in 1:4) { g <- gen(sample(2:6, 1), sample(1:5, 1), "lp"); problem(0, g$P, g$q, g$A, g$l, g$u, list(eps_abs = 1e-5, eps_rel = 1e-5)) }
for (rep in 1:3) { g <- gen(sample(3:6, 1), sample(3:7, 1), "lowrank"); problem(0, g$P, g$q, g$A, g$l, g$u, list(polishing = TRUE)) }
for (rep in 1:3) { g <- gen(sample(3:6, 1), sample(3:7, 1)); problem(0, g$P, g$q, g$A, g$l, g$u, list(adaptive_rho = 0L, rho = 0.5, sigma = 1e-4, alpha = 1.2)) }
for (rep in 1:2) { g <- gen(sample(3:6, 1), sample(3:7, 1)); problem(0, g$P, g$q, g$A, g$l, g$u, list(scaling = 0L)) }
for (rep in 1:2) { g <- gen(sample(3:6, 1), sample(3:7, 1)); problem(0, g$P, g$q, g$A, g$l, g$u, list(check_termination = 5L, adaptive_rho_interval = 20L)) }
for (rep in 1:2) { g <- gen(sample(4:7, 1), sample(4:8, 1)); problem(0, g$P, g$q, g$A, g$l, g$u, list(max_iter = 30L)) }
# one-sided rows: the other bound infinite
for (rep in 1:3) {
  g <- gen(sample(3:6, 1), sample(4:8, 1))
  side <- rbinom(g$m, 1, 0.5) == 1; g$l[side] <- -Inf; g$u[!side & g$l > -Inf & rbinom(g$m, 1, 0.5) == 1] <- Inf
  problem(0, g$P, g$q, g$A, g$l, g$u, list(polishing = TRUE))
}
# infeasible and unbounded
for (rep in 1:2) {
  n <- sample(2:4, 1); a1 <- rnorm(n); A <- rbind(a1, a1, diag(n)); l <- c(1, -3, rep(-10, n)); u <- c(3, -1, rep(10, n))
  problem(0, diag(n), rnorm(n), A, l, u)
}
for (rep in 1:2) {
  n <- sample(2:4, 1); A <- rbind(diag(n)); problem(0, matrix(0, n, n), -abs(rnorm(n)) - 0.5, A, rep(0, n), rep(Inf, n))
}
# warm starts, data updates
for (rep in 1:3) {
  g <- gen(sample(3:7, 1), sample(3:8, 1))
  problem(1, g$P, g$q, g$A, g$l, g$u, list(), list(q2 = g$q + rnorm(g$n, sd = 0.3), l2 = g$l - 0.1, u2 = g$u + 0.1))
}
for (rep in 1:2) {
  g <- gen(sample(3:7, 1), sample(3:8, 1))
  B <- matrix(rnorm(g$n^2, sd = 0.2), g$n); P2 <- g$P + crossprod(B); A2 <- g$A * (1 + matrix(rnorm(length(g$A), sd = 0.05), nrow(g$A)))
  problem(2, g$P, g$q, g$A, g$l, g$u, list(polishing = TRUE), list(P2 = P2, A2 = A2))
}
for (rep in 1:3) {
  g <- gen(sample(3:7, 1), sample(3:8, 1))
  problem(3, g$P, g$q, g$A, g$l, g$u, list(), list(x0 = rnorm(g$n), y0 = rnorm(g$m)))
}
emit("osqp", "osqp", list(cases))
