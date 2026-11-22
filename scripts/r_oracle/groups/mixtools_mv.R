# mixtools: mvnormalmixEM, random starts included (set.seed is called just before the fit, after the data are drawn).
#   mv   args: (sel, idx, seed, k, arbmean, arbvar, n, p, nl, nmu, nsg, x[n x p, row-major], lambda[nl], mu[nmu], sigma[nsg])
#        mu is k x p row-major (p values when arbmean is 0), sigma k blocks of p x p (one block when arbvar is 0)
#        sel 1 loglik, 2 iterations, 3 restarts, 4 lambda[idx], 5 mu[idx], 6 sigma[idx], 7 sum_i posterior[i, idx] * i, 8 all.loglik[idx], 9 length(all.loglik)
suppressMessages(library(mixtools))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
quiet <- function(e) { r <- NULL; capture.output(r <- try(suppressWarnings(e), silent = TRUE)); r }
rows <- function(m) as.vector(t(m))
mv_case <- function(x, k, arbmean, arbvar, lam, mu, sg, seed) {
  n <- nrow(x); p <- ncol(x)
  set.seed(seed)
  mul <- if (length(mu)) { if (arbmean) lapply(1:k, function(j) mu[((j - 1) * p + 1):(j * p)]) else mu } else NULL
  sgl <- if (length(sg)) { if (arbvar) lapply(1:k, function(j) matrix(sg[((j - 1) * p * p + 1):(j * p * p)], p, p, byrow = TRUE)) else matrix(sg, p, p, byrow = TRUE) } else NULL
  r <- quiet(mvnormalmixEM(x, lambda = if (length(lam)) lam else NULL, mu = mul, sigma = sgl, k = k, arbmean = as.logical(arbmean), arbvar = as.logical(arbvar), epsilon = 1e-8, maxit = 1000))
  if (inherits(r, "try-error") || length(r$all.loglik) > 1000) return(invisible())
  hd <- c(seed, k, arbmean, arbvar, n, p, length(lam), length(mu), length(sg), rows(x), lam, mu, sg)
  a <- function(sel, idx, want, rel = 1e-9) add("mv", c(sel, idx, hd), want, rel = rel)
  a(1, 0, r$loglik); a(2, 0, length(r$all.loglik) - 1, rel = 0); a(3, 0, r$restarts, rel = 0)
  for (j in seq_len(k)) { a(4, j, r$lambda[j]); a(7, j, sum(r$posterior[, j] * seq_len(n))) }
  mus <- if (arbmean) unlist(r$mu) else r$mu
  for (j in seq_along(mus)) a(5, j, mus[j])
  sgs <- if (arbvar) unlist(lapply(r$sigma, rows)) else rows(r$sigma)
  for (j in seq_along(sgs)) a(6, j, sgs[j])
  a(8, 1, r$all.loglik[1]); a(8, length(r$all.loglik), r$all.loglik[length(r$all.loglik)]); a(9, 0, length(r$all.loglik), rel = 0)
}
mvdraw <- function(k, p, n) {
  lam <- runif(k); lam <- lam / sum(lam); comp <- sample(k, n, replace = TRUE, prob = lam)
  mus <- matrix(rnorm(k * p, 0, 3), k, p); L <- chol(crossprod(matrix(rnorm(p * p), p, p)) / p + diag(p) * 0.5)
  round(mus[comp, , drop = FALSE] + matrix(rnorm(n * p), n, p) %*% L, 4)
}
set.seed(20261301)
for (rep in 1:4) {                          # given starting values, both constraint sets on the covariances
  k <- 2; p <- sample(2:3, 1); n <- sample(40:90, 1); x <- mvdraw(k, p, n)
  q <- order(rowMeans(x)); b1 <- x[q[1:(n %/% 2)], , drop = FALSE]; b2 <- x[q[(n %/% 2 + 1):n], , drop = FALSE]
  mu <- c(colMeans(b1), colMeans(b2)); sg <- c(rows(cov(b1)), rows(cov(b2)))
  mv_case(x, k, 1, 1, c(0.5, 0.5), mu, sg, 1)
  mv_case(x, k, 1, 0, c(0.4, 0.6), mu, rows(cov(x)), 2)
}
for (rep in 1:8) {                          # random starts
  k <- sample(2:3, 1); p <- sample(2:3, 1); n <- sample(40:90, 1); x <- mvdraw(k, p, n)
  mv_case(x, k, 1, 1, numeric(0), numeric(0), numeric(0), 100 + rep)
  if (rep %% 2 == 0) mv_case(x, k, 1, 0, numeric(0), numeric(0), numeric(0), 200 + rep)
  if (rep %% 3 == 0) mv_case(x, k, 0, 1, numeric(0), numeric(0), numeric(0), 300 + rep)
}

emit("mixtools_mv", "mixtools", list(cases))
