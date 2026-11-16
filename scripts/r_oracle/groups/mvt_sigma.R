# mvtnorm pmvnorm with a mean and a covariance matrix (sigma), Genz-Bretz under a seed.
#   args: (seed, n, maxpts, abseps, releps, lower[n], upper[n], mean[n], sigma row-major[n*n], q); +-Inf are +-1e308
#   q 0 value, 1 error
suppressMessages(library(mvtnorm))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("mvt_sigma", args, want, rel = 1e-9, abs = 1e-12)
inf2 <- function(x) ifelse(is.infinite(x), sign(x) * 1e308, x)
set.seed(20261119)
for (rep in 1:80) {
  n <- sample(2:6, 1)
  a <- matrix(rnorm(n * n), n, n); sg <- crossprod(a) + diag(runif(n, 0.2, 1))
  if (rep %% 8 == 0) sg <- cov2cor(sg)
  mean <- round(rnorm(n, 0, 1), 2)
  lo <- round(rnorm(n, -1, 1), 2); up <- lo + round(runif(n, 0.2, 3), 2)
  kind <- sample(0:4, n, TRUE)
  lo[kind == 1] <- -Inf; up[kind == 2] <- Inf; lo[kind == 3] <- -Inf; up[kind == 3] <- Inf
  if (all(is.infinite(lo) & is.infinite(up))) next
  mp <- sample(c(25000, 1000, 100000), 1); ae <- sample(c(1e-3, 1e-5), 1); re <- sample(c(0, 1e-3), 1)
  seed <- sample(1e6, 1)
  r <- tryCatch(pmvnorm(lo, up, mean = mean, sigma = sg, algorithm = GenzBretz(maxpts = mp, abseps = ae, releps = re), seed = seed), error = function(e) NULL)
  if (is.null(r)) next
  base <- c(seed, n, mp, ae, re, inf2(lo), inf2(up), mean, as.vector(t(sg)))
  add(c(base, 0), as.numeric(r)); add(c(base, 1), attr(r, "error"))
}
emit("mvt_sigma", "mvtnorm", list(cases))
