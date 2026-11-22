# glasso::glasso, glasso::glassopath and qgraph::EBICglasso on random covariance matrices.
#   fn "gl_w" "gl_wi" "gl_niter" "gl_del" "gl_loglik":
#     args (p, ia, ipen, thr, maxit, nobs, nrho, rho[nrho], nz, zero[2 nz] 1-based pairs, S[p*p] column-major)
#     want: position-weighted sum of w / wi, niter, del, loglik
#   fn "path_w" "path_wi": args (p, nrho, ia, ipen, rholist[nrho] ascending, S) over the nrho p*p estimates
#   fn "ebic_net" "ebic_val" "ebic_lambda":
#     args (p, n, gamma, penDiag, nlambda, lmr, countDiag, refit, threshold, S); net, weighted sum of EBICs, lambda at the minimum
suppressMessages(library(glasso))
suppressMessages(library(qgraph))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
ws <- function(v) sum(as.vector(v) * seq_along(as.vector(v)))
rcov <- function(p, nobs, corr) {
  A <- matrix(rnorm(p * p), p, p); L <- diag(p) + corr * A %*% t(A) / p
  x <- matrix(rnorm(nobs * p), nobs, p) %*% chol(L)
  cov(x) * ifelse(corr > 0.5, 1, 1.7)
}
set.seed(20271101)
for (it in 1:36) {
  p <- sample(3:9, 1); S <- rcov(p, sample(40:200, 1), runif(1, 0.1, 1.2))
  ia <- as.integer(it %% 6 == 0); ipen <- as.integer(it %% 2 == 0)
  vec <- it %% 3 == 0
  rho <- if (vec) runif(p, 0.02, 0.4) else runif(1, 0.02, 0.5)
  sdv <- sqrt(diag(S)); thr <- c(1e-4, 1e-6, 1e-8)[1 + it %% 3]; maxit <- if (it %% 11 == 0) 3 else 10000
  nz <- if (it %% 4 == 0) 2 else 0
  zero <- NULL; if (nz > 0) { zero <- rbind(c(1, 2), c(2, p)); }
  nobs <- sample(50:300, 1)
  r <- suppressWarnings(glasso(S, rho, nobs = nobs, zero = zero, thr = thr, maxit = maxit, approx = ia == 1, penalize.diagonal = ipen == 1))
  a <- c(p, ia, ipen, thr, maxit, nobs, length(rho), rho, nz, if (nz > 0) as.vector(t(zero)), as.vector(S))
  add("gl_w", a, ws(r$w)); add("gl_wi", a, ws(r$wi)); add("gl_niter", a, r$niter, rel = 0, abs = 0)
  add("gl_del", a, r$del); add("gl_loglik", a, r$loglik)
}
# decoupled blocks: a penalty that splits the graph into components, singletons included
for (it in 1:8) {
  p <- sample(5:10, 1); S <- rcov(p, 120, 0.4); S[1, 2:3] <- S[2:3, 1] <- 0; S[2, 3] <- S[3, 2] <- 0
  rho <- runif(1, 0.15, 0.45)
  r <- suppressWarnings(glasso(S, rho, nobs = 100, penalize.diagonal = it %% 2 == 0))
  a <- c(p, 0, as.integer(it %% 2 == 0), 1e-4, 10000, 100, 1, rho, 0, as.vector(S))
  add("gl_w", a, ws(r$w)); add("gl_wi", a, ws(r$wi)); add("gl_niter", a, r$niter, rel = 0, abs = 0); add("gl_del", a, r$del)
}
for (it in 1:12) {
  p <- sample(3:8, 1); S <- rcov(p, 100, 0.5); mx <- max(abs(S[upper.tri(S)])); nr <- sample(2:6, 1)
  rl <- sort(runif(nr, 0.01, mx)); ia <- as.integer(it %% 4 == 0); ipen <- as.integer(it %% 2 == 0)
  r <- suppressWarnings(glassopath(S, rl, trace = 0, approx = ia == 1, penalize.diagonal = ipen == 1))
  a <- c(p, nr, ia, ipen, rl, as.vector(S))
  add("path_w", a, ws(r$w)); add("path_wi", a, ws(r$wi))
}
for (it in 1:30) {
  p <- sample(4:12, 1); n <- sample(80:400, 1); S <- rcov(p, n, runif(1, 0.1, 1.5)); S <- cov2cor(S) * 1; S <- S * c(1, 2.5)[1 + it %% 2]
  S <- S * outer(sqrt(runif(p, 0.5, 2)), sqrt(runif(p, 0.5, 2)))
  S <- (S + t(S)) / 2
  gam <- c(0.5, 0, 0.25, 1)[1 + it %% 4]; pd <- it %% 5 == 0; nl <- c(100, 30, 50)[1 + it %% 3]; lmr <- c(0.01, 0.1, 0.001)[1 + it %% 3]
  cd <- it %% 7 == 0; refit <- it %% 3 == 1; th <- it %% 9 == 0
  r <- suppressMessages(suppressWarnings(EBICglasso(S, n, gamma = gam, penalize.diagonal = pd, nlambda = nl, lambda.min.ratio = lmr, returnAllResults = TRUE,
                                  countDiagonal = cd, refit = refit, threshold = th, checkPD = FALSE, verbose = FALSE)))
  a <- c(p, n, gam, pd, nl, lmr, cd, refit, th, as.vector(S))
  add("ebic_net", a, ws(r$optnet)); add("ebic_val", a, ws(r$ebic)); add("ebic_lambda", a, r$lambda[which.min(r$ebic)])
  if (it %in% c(4, 9, 12)) for (k in seq_along(r$ebic)) { add("ebic_at", c(a, k), r$ebic[k]); add("lam_at", c(a, k), r$lambda[k], rel = 0, abs = 0) }
}
set.seed(7); for (x in runif(40, 0.05, 1)) { add("explog", x, exp(log(x)), rel = 0, abs = 0); add("lg", x * 0.1, log(x * 0.1), rel = 0, abs = 0); add("ex", -4 * x, exp(-4 * x), rel = 0, abs = 0) }
emit("glasso", c("glasso", "qgraph"), list(cases))
