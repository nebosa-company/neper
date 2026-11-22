# mixtools: npEM and spEMsymloc (kmeans starts with given or drawn centers, the stochastic variants too).
#   sp   args: (sel, idx, seed, m, hasc, bw, maxit, stoch, n, x[n], centers[m])      bw 0 is the default bw.nrd0(x)
#        sel 1 iterations (nrow of lambda), 2 lambdahat[idx], 3 muhat[idx], 4 sum_i posterior[i, idx] * i, 5 lambda[1, idx], 6 mu[nrow, idx], 7 lambda[nrow, idx], 8 mu[1, idx]
#   np   args: (sel, idx, seed, m, hasc, samebw, stoch, bw, maxit, n, r, x[n x r, row-major], blockid[r], centers[m x r, row-major])   bw 0 is the default
#        sel 1 iterations, 2 lambdahat[idx], 3 sum_i posterior[i, idx] * i, 4 lambda[1, idx], 5 loglik[idx], 6 bandwidth[idx] (row-major nb x m, or the scalar), 7 length(loglik)
suppressMessages(library(mixtools))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
quiet <- function(e) { r <- NULL; capture.output(r <- try(suppressWarnings(e), silent = TRUE)); r }
rows <- function(m) as.vector(t(m))
sp_case <- function(x, m, cen, bw, maxit, stoch, seed) {
  n <- length(x)
  set.seed(seed)
  r <- quiet(if (bw > 0) spEMsymloc(x, if (length(cen)) cen else m, bw = bw, maxiter = maxit, stochastic = as.logical(stoch), eps = 1e-8)
             else spEMsymloc(x, if (length(cen)) cen else m, maxiter = maxit, stochastic = as.logical(stoch), eps = 1e-8))
  if (inherits(r, "try-error")) return(invisible())
  hd <- c(seed, m, length(cen) > 0, bw, maxit, stoch, n, x, cen)
  a <- function(sel, idx, want, rel = 1e-9) add("sp", c(sel, idx, hd), want, rel = rel)
  nr <- nrow(r$lambda)
  a(1, 0, nr, rel = 0)
  for (j in seq_len(m)) { a(2, j, r$lambdahat[j]); a(3, j, r$muhat[j]); a(4, j, sum(r$posterior[, j] * seq_len(n))); a(5, j, r$lambda[1, j]); a(6, j, r$mu[nr, j]); a(7, j, r$lambda[nr, j]); a(8, j, r$mu[1, j]) }
}
np_case <- function(x, m, cen, blockid, samebw, stoch, bw, maxit, seed) {
  n <- nrow(x); r <- ncol(x)
  set.seed(seed)
  mu0 <- if (length(cen)) matrix(cen, m, r, byrow = TRUE) else m
  f <- quiet(if (bw > 0) npEM(x, mu0, blockid = blockid, bw = bw, samebw = as.logical(samebw), eps = 1e-8, maxiter = maxit, stochastic = as.logical(stoch), verb = FALSE)
             else npEM(x, mu0, blockid = blockid, samebw = as.logical(samebw), eps = 1e-8, maxiter = maxit, stochastic = as.logical(stoch), verb = FALSE))
  if (inherits(f, "try-error")) return(invisible())
  hd <- c(seed, m, length(cen) > 0, samebw, stoch, bw, maxit, n, r, rows(x), blockid, cen)
  a <- function(sel, idx, want, rel = 1e-9) add("np", c(sel, idx, hd), want, rel = rel)
  nr <- nrow(f$lambda)
  a(1, 0, nr, rel = 0); a(7, 0, length(f$loglik), rel = 0)
  for (j in seq_len(m)) { a(2, j, f$lambdahat[j]); a(3, j, sum(f$posteriors[, j] * seq_len(n))); a(4, j, f$lambda[1, j]) }
  for (j in seq_along(f$loglik)) if (j == 1 || j == length(f$loglik)) a(5, j, f$loglik[j])
  b <- as.vector(if (samebw) f$bandwidth else t(f$bandwidth))
  for (j in seq_along(b)) a(6, j, b[j])
}
set.seed(20261401)
for (rep in 1:10) {                          # spEMsymloc
  n <- sample(40:80, 1); m <- 2; cen <- sort(runif(2, -3, 3)) + c(-2, 2); lam <- runif(1, 0.3, 0.7)
  comp <- runif(n) < lam; x <- round(ifelse(comp, rnorm(n, cen[1], 1), rnorm(n, cen[2], 1.2)), 4)
  sp_case(x, 2, cen, 0, 100, 0, 1)
  sp_case(x, 2, numeric(0), 0.8, 100, 0, 10 + rep)
  if (rep %% 2 == 0) sp_case(x, 2, cen + 0.3, 0.7, 30, 1, 20 + rep)
}
for (rep in 1:9) {                           # npEM
  n <- sample(30:60, 1); r <- sample(3:4, 1); m <- 2
  g <- sample(m, n, replace = TRUE); mus <- matrix(c(-1.5, 1.5)[1:m], m, r) + matrix(rnorm(m * r, 0, 0.4), m, r)
  x <- round(matrix(rnorm(n * r, mus[g, ], 1), n, r), 4)
  cen <- rows(mus)
  bl <- if (rep %% 3 == 0) c(1, 1, 2, 2)[1:r] else 1:r
  np_case(x, m, cen, bl, 1, 0, 0, 200, 1)
  np_case(x, m, numeric(0), bl, 1, 0, 0.5, 200, 30 + rep)
  np_case(x, m, cen, bl, 0, 0, 0, 200, 2)
  if (rep %% 2 == 0) np_case(x, m, cen, bl, 1, 1, 0.5, 40, 40 + rep)
  if (rep %% 3 == 1) np_case(x, m, cen, bl, 0, 1, 0, 40, 50 + rep)
}

emit("mixtools_np", "mixtools", list(cases))
