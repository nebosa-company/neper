# mvtnorm qmvnorm (Genz-Bretz, equicoordinate, correlation input) under a seed: the quantile and the fitted probability minus p.
#   args: (seed, n, tail 0 lower 1 upper 2 both, p, ptol, maxiter, corr row-major[n*n]); fn "q" the quantile, "fq" f.quantile
suppressMessages(library(mvtnorm))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-6, abs = 1e-8)
set.seed(20261119)
rcorr <- function(n) { a <- matrix(rnorm(n * n), n, n); s <- crossprod(a) + diag(runif(n, 0.2, 1)); cov2cor(s) }
for (rep in 1:40) {
  n <- sample(3:5, 1); corr <- rcorr(n); if (rep %% 6 == 0) corr <- diag(n) * 0.5 + 0.5
  tail <- sample(0:2, 1); p <- if (tail == 2) round(runif(1, 0.6, 0.99), 3) else round(runif(1, 0.05, 0.95), 3)
  seed <- sample(1e6, 1); ptol <- sample(c(0.001, 0.005), 1)
  r <- tryCatch(qmvnorm(p, tail = c("lower.tail", "upper.tail", "both.tails")[tail + 1], corr = corr, seed = seed, ptol = ptol), error = function(e) NULL)
  if (is.null(r) || !is.finite(r$quantile)) next
  a <- c(seed, n, tail, p, ptol, 500, as.vector(t(corr)))
  add("q", a, r$quantile); add("fq", a, r$f.quantile)
}
emit("qmvnorm", "mvtnorm", list(cases))
