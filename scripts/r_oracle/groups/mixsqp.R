# mixsqp: the mixture proportions and the objective value on likelihood matrices.
#   args: (n, m, L[n*m] column-major, w[n], q)  q 0..m-1 x, m value
suppressMessages(library(mixsqp))
cases <- list()
set.seed(20261116)
for (rep in 1:20) {
  n <- sample(30:150, 1); m <- sample(3:10, 1); s <- c(0.5, 1, 2)[rep %% 3 + 1]
  L <- round(exp(matrix(rnorm(n * m) * s, n, m)), 6); w <- if (rep %% 2 == 0) round(runif(n, 0.2, 3), 3) else rep(1, n)
  r <- mixsqp(L, w, control = list(verbose = FALSE, convtol.sqp = 1e-12, convtol.activeset = 1e-12, maxiter.sqp = 1000))
  out <- c(r$x, r$value)
  for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("mix", c(n, m, L, w, q - 1), out[q], rel = 1e-5, abs = 1e-5)
}
# the SQP itself ("sqp", tol.svd = 0 so the full matrix is used): q 0..m-1 x, m value, m+1 status (0 converged), m+2 progress rows, m+3 sum of nqp, m+4 sum of nls, m+5 nonzeros at the end
for (rep in 1:30) {
  n <- sample(30:150, 1); m <- sample(3:12, 1); s <- c(0.5, 1, 2, 3)[rep %% 4 + 1]
  L <- round(exp(matrix(rnorm(n * m) * s, n, m)), 6); w <- if (rep %% 2 == 0) round(runif(n, 0.2, 3), 3) else rep(1, n)
  r <- suppressWarnings(mixsqp(L, w, control = list(verbose = FALSE, tol.svd = 0)))
  p <- r$progress
  out <- c(r$x, r$value, if (r$status == "converged to optimal solution") 0 else 1, nrow(p), sum(p$nqp, na.rm = TRUE), sum(p$nls, na.rm = TRUE), p$nnz[nrow(p)], sum(r$grad), sum(r$hessian))
  for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("sqp", c(n, m, L, w, q - 1), out[q], rel = if (q <= m + 1 || q > m + 6) 1e-6 else 0, abs = if (q <= m + 1 || q > m + 6) 1e-8 else 0)
}
# zero columns (the weight is zero and the rest is solved), the trivial single column, and log-likelihood input ("sqplog")
for (rep in 1:12) {
  n <- sample(30:100, 1); m <- sample(4:9, 1); L <- round(exp(matrix(rnorm(n * m) * 1.5, n, m)), 6); w <- round(runif(n, 0.2, 3), 3)
  kind <- rep %% 3
  if (kind == 0) { zc <- sample(m, 2); L[, zc] <- 0 } else if (kind == 1) { zc <- sample(m, 1); L[, zc] <- 0 }
  nm <- if (kind == 2) "sqplog" else "sqp"
  Lin <- if (kind == 2) log(L) else L
  r <- suppressWarnings(mixsqp(Lin, w, log = kind == 2, control = list(verbose = FALSE, tol.svd = 0)))
  p <- r$progress
  out <- c(r$x, r$value, if (r$status == "converged to optimal solution") 0 else 1, nrow(p), sum(p$nqp, na.rm = TRUE), sum(p$nls, na.rm = TRUE), p$nnz[nrow(p)], sum(r$grad), sum(r$hessian))
  for (q in seq_along(out)) cases[[length(cases) + 1]] <- case(nm, c(n, m, Lin, w, q - 1), out[q], rel = if (q <= m + 1 || q > m + 6) 1e-6 else 0, abs = if (q <= m + 1 || q > m + 6) 1e-8 else 0)
}
for (rep in 1:3) {
  n <- 20; m <- 5; L <- round(exp(matrix(rnorm(n * m), n, m)), 6); L[, -rep] <- 0; w <- rep(1, n)
  r <- suppressWarnings(mixsqp(L, w, control = list(verbose = FALSE, tol.svd = 0)))
  for (q in 1:(m + 2)) cases[[length(cases) + 1]] <- case("sqp", c(n, m, L, w, q - 1), c(r$x, r$value, 2)[q], rel = 1e-9, abs = 1e-9)
}
# argument validation (fn "val"): args (n, m, L, w, x0, convtol.sqp, convtol.activeset, zero.threshold.solution, zero.threshold.searchdir, suffdecr.linesearch, stepsizereduce, minstepsize, identity.contrib.increase, eps, maxiter.sqp, maxiter.activeset (0 is NULL), numiter.em); the value is the code of the first failed check (0 passes)
code_of <- function(e) {
  m <- conditionMessage(e)
  if (grepl("Input argument \"L\"", m)) 1 else if (grepl("Input argument \"w\"", m)) 2 else if (grepl("\"x0\" should be", m)) 3 else if (grepl("not a valid initial", m)) 4
  else if (grepl("maxiter.activeset", m)) 5 else if (grepl("maxiter.sqp", m)) 6 else if (grepl("non-negative number", m)) 7 else if (grepl("stepsizereduce", m)) 8 else if (grepl("unpredictable", m)) 9 else 99
}
for (rep in 1:300) {
  n <- sample(3:12, 1); m <- sample(2:6, 1); L <- round(matrix(runif(n * m, 0.1, 2), n, m), 3); w <- round(runif(n, 0.2, 2), 2); x0 <- rep(1, m)
  ct <- c(1e-8, 1e-10, 1e-8, 1e-14, 0.01, 0.75, 1e-8, 10, 1e-8); ms <- 1000; ma <- 0; ne <- 10
  k <- sample(0:14, 1)
  if (k == 1) L[sample(length(L), 1)] <- -0.5
  if (k == 2) L[sample(length(L), 1)] <- NaN
  if (k == 3) L[] <- 0
  if (k == 4) w[sample(n, 1)] <- -1
  if (k == 5) x0[sample(m, 1)] <- -1
  if (k == 6) { L[1, ] <- 0; x0 <- c(1, rep(0, m - 1)); L[1, 1] <- 0; if (m > 1) L[1, 2] <- 0.5 }
  if (k == 7) ms <- sample(c(0, -3, 1.5), 1)
  if (k == 8) ma <- sample(c(-2, 2.5), 1)
  if (k == 9) ct[sample(c(1, 2, 3, 4, 5, 7, 9), 1)] <- -1
  if (k == 10) ne <- -1
  if (k == 11) ct[6] <- sample(c(0, 1, 1.5), 1)
  if (k == 12) ct[sample(c(5, 7, 8), 1)] <- 0
  if (k == 13) ct[3] <- 1 / m
  if (k == 14) ct[sample(c(1, 2), 1)] <- Inf
  ctl <- list(verbose = FALSE, convtol.sqp = ct[1], convtol.activeset = ct[2], zero.threshold.solution = ct[3], zero.threshold.searchdir = ct[4], suffdecr.linesearch = ct[5], stepsizereduce = ct[6], minstepsize = ct[7], identity.contrib.increase = ct[8], eps = ct[9], maxiter.sqp = ms, numiter.em = ne)
  if (ma != 0) ctl$maxiter.activeset <- ma
  code <- tryCatch({ suppressWarnings(mixsqp(L, w, x0, control = ctl)); 0 }, error = function(e) code_of(e))
  if (code == 99) next
  cases[[length(cases) + 1]] <- case("val", c(n, m, L, w, x0, ct, ms, ma, ne), code, rel = 0, abs = 0)
}
emit("mixsqp", "mixsqp", list(cases))
