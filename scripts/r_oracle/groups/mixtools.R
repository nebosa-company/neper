# mixtools: normalmixEM and multmixEM, random starts included (set.seed is called just before the fit, after the data are drawn).
#   nm   args: (sel, idx, seed, k, arbmean, arbvar, n, nl, nm, ns, x[n], lambda[nl], mu[nm], sigma[ns])
#        sel 1 loglik, 2 iterations, 3 restarts, 4 lambda[idx], 5 mu[idx], 6 sigma[idx], 7 scale[idx], 8 sum_i posterior[i, idx] * i, 9 all.loglik[idx], 10 length(all.loglik)
#   mm   args: (sel, idx, seed, k, n, p, nl, nt, y[n x p, row-major], lambda[nl], theta[nt, k x p row-major])
#        sel 1 loglik, 2 iterations, 3 restarts, 4 lambda[idx], 5 theta[idx], 6 sum_i posterior[i, idx] * i, 7 all.loglik[idx], 8 length(all.loglik)
suppressMessages(library(mixtools))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
quiet <- function(e) { r <- NULL; capture.output(r <- try(suppressWarnings(e), silent = TRUE)); r }
nm_case <- function(x, k, arbmean, arbvar, lam, mu, sg, seed) {
  set.seed(seed)
  r <- quiet(normalmixEM(x, lambda = if (length(lam)) lam else NULL, mu = if (length(mu)) mu else NULL, sigma = if (length(sg)) sg else NULL,
                         k = k, arbmean = arbmean, arbvar = arbvar, epsilon = 1e-8, maxit = 1000))
  if (inherits(r, "try-error") || length(r$all.loglik) > 1000) return(invisible())
  hd <- c(seed, k, arbmean, arbvar, length(x), length(lam), length(mu), length(sg), x, lam, mu, sg)
  a <- function(sel, idx, want, rel = 1e-9) add("nm", c(sel, idx, hd), want, rel = rel)
  K <- length(r$lambda)
  a(1, 0, r$loglik); a(2, 0, length(r$all.loglik) - 1, rel = 0); a(3, 0, r$restarts, rel = 0)
  for (j in seq_len(K)) { a(4, j, r$lambda[j]); a(8, j, sum(r$posterior[, j] * seq_along(x))) }
  for (j in seq_along(r$mu)) a(5, j, r$mu[j])
  for (j in seq_along(r$sigma)) a(6, j, r$sigma[j])
  if (!arbmean) for (j in seq_len(K)) a(7, j, r$scale[j])
  a(9, 1, r$all.loglik[1]); a(9, 2, r$all.loglik[2]); a(9, length(r$all.loglik), r$all.loglik[length(r$all.loglik)]); a(10, 0, length(r$all.loglik), rel = 0)
}
draw <- function() {
  k <- sample(2:3, 1); n <- sample(60:140, 1); mus <- sort(runif(k, -4, 4)) * c(1, 1.5, 2)[1:k]; sds <- runif(k, 0.5, 1.5); lam <- runif(k); lam <- lam / sum(lam)
  comp <- sample(k, n, replace = TRUE, prob = lam); list(k = k, x = round(rnorm(n, mus[comp], sds[comp]), 4))
}
set.seed(20261227)
for (rep in 1:10) {                       # given starting values
  d <- draw(); k <- d$k; x <- d$x
  nm_case(x, k, 1, 1, rep(1 / k, k), as.numeric(quantile(x, seq(0.2, 0.8, length.out = k))), rep(sd(x) / 2, k), 1)
}
for (rep in 1:16) {                       # random starts, the four constraint sets
  d <- draw()
  nm_case(d$x, d$k, c(1, 1, 0, 0)[rep %% 4 + 1], c(1, 0, 1, 0)[rep %% 4 + 1] * 1, numeric(0), numeric(0), numeric(0), 100 + rep)
}
for (rep in 1:4) {                        # random mu only, then sigma only
  d <- draw(); k <- d$k; x <- d$x
  nm_case(x, k, 1, 1, rep(1 / k, k), numeric(0), rep(sd(x) / 2, k), 200 + rep)
  nm_case(x, k, 1, 1, numeric(0), as.numeric(quantile(x, seq(0.2, 0.8, length.out = k))), numeric(0), 300 + rep)
}

mm_case <- function(y, k, lam, th, seed) {
  set.seed(seed)
  p <- ncol(y)
  r <- quiet(multmixEM(y, lambda = if (length(lam)) lam else NULL, theta = if (length(th)) matrix(th, ncol = p, byrow = TRUE) else NULL, k = k, epsilon = 1e-8, maxit = 10000))
  if (inherits(r, "try-error")) return(invisible())
  hd <- c(seed, k, nrow(y), p, length(lam), length(th), as.vector(t(y)), lam, th)
  a <- function(sel, idx, want, rel = 1e-9) add("mm", c(sel, idx, hd), want, rel = rel)
  K <- length(r$lambda)
  a(1, 0, r$loglik); a(2, 0, length(r$all.loglik), rel = 0); a(3, 0, r$restarts, rel = 0)
  for (j in seq_len(K)) { a(4, j, r$lambda[j]); a(6, j, sum(r$posterior[, j] * seq_len(nrow(y)))) }
  th2 <- as.vector(t(r$theta)); for (j in seq_along(th2)) a(5, j, th2[j])
  a(7, 1, r$all.loglik[1]); a(7, length(r$all.loglik), r$all.loglik[length(r$all.loglik)]); a(8, 0, length(r$all.loglik), rel = 0)
}
for (rep in 1:12) {
  k <- sample(2:3, 1); p <- sample(3:5, 1); n <- sample(40:90, 1); m <- sample(20:60, 1)
  th <- matrix(rgamma(k * p, 1.5), k, p); th <- th / rowSums(th); lam <- runif(k); lam <- lam / sum(lam)
  comp <- sample(k, n, replace = TRUE, prob = lam)
  y <- t(sapply(comp, function(cc) rmultinom(1, m, th[cc, ])))
  if (rep <= 6) mm_case(y, k, numeric(0), numeric(0), 400 + rep)                     # random starts
  else mm_case(y, k, rep(1 / k, k), as.vector(t(th)) * 0 + as.vector(t(matrix(rep(colSums(y) / sum(y), k), k, p, byrow = TRUE) * (1 + 0.3 * (row(th) - 1) * (col(th) - 1.5)))), 500 + rep)
}

emit("mixtools", "mixtools", list(cases))
