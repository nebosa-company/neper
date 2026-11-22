# kernlab ipop (interior point QP, square H) on random strictly convex problems with bounds, one or two range constraints.
#   args: (n, m, sigf, maxiter, margin, bound, c[n], l[n], u[n], r[m], b[m], H[n*n] row-major, A[m*n] row-major)
#   fn "primal" and "dual" (position-weighted solution vectors)
suppressMessages(library(kernlab))
cases <- list()
add <- function(fn, args, want, rel = 1e-10, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
ws <- function(v) sum(as.vector(v) * seq_along(v))
set.seed(20261302)
for (rep in 1:24) {
  n <- sample(3:9, 1); m <- sample(1:2, 1)
  Z <- matrix(rnorm(n * n), n); H <- crossprod(Z) / n + diag(0.3, n)
  cc <- rnorm(n); l <- -runif(n, 0.5, 2); u <- runif(n, 0.5, 2)
  A <- matrix(rnorm(m * n), m); x0 <- l + (u - l) * runif(n); r <- runif(m, 0.5, 2); b <- as.vector(A %*% x0) - 0.5 * r
  sigf <- if (rep %% 3 == 0) 9 else 7; margin <- if (rep %% 4 == 0) 0.1 else 0.05; bound <- if (rep %% 5 == 0) 5 else 10
  res <- ipop(cc, H, A, b, l, u, r, sigf = sigf, maxiter = 60, margin = margin, bound = bound)
  if (how(res) != "converged") next
  a <- c(n, m, sigf, 60, margin, bound, cc, l, u, r, b, as.vector(t(H)), as.vector(t(A)))
  add("primal", a, ws(primal(res))); add("dual", a, ws(dual(res)))
}
emit("kernlabqp", "kernlab", list(cases))
