# osqp solve_osqp on random strictly convex QPs with two-sided constraints (some equalities), tight tolerances.
#   args: (n, m, P[n*n], q[n], A[m*n] row-major, l[m], u[m])
#   fn "obj" (objective value), "x" (solution weighted by position)
suppressMessages({library(osqp); library(Matrix)})
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-6, abs = 1e-8)
set.seed(20270105)
for (rep in 1:24) {
  n <- sample(2:8, 1); m <- sample(2:10, 1); B <- matrix(rnorm(n * n), n); P <- crossprod(B) + diag(n) * runif(1, 0.2, 2)
  q <- rnorm(n); A <- matrix(rnorm(m * n), m); x0 <- rnorm(n); l <- as.vector(A %*% x0 - runif(m)); u <- as.vector(A %*% x0 + runif(m))
  eq <- rbinom(m, 1, 0.2) == 1; l[eq] <- u[eq] <- as.vector(A %*% x0)[eq]
  r <- tryCatch(solve_osqp(Matrix(P, sparse = TRUE), q, Matrix(A, sparse = TRUE), l, u, osqpSettings(eps_abs = 1e-12, eps_rel = 1e-12, max_iter = 1000000L, verbose = FALSE, polishing = TRUE)), error = function(e) NULL)
  if (is.null(r) || r$info$status != "solved") next
  a <- c(n, m, as.vector(t(P)), q, as.vector(t(A)), l, u)
  add("obj", a, r$info$obj_val); add("x", a, sum(r$x * seq_along(r$x)))
}
emit("osqp", "osqp", list(cases))
