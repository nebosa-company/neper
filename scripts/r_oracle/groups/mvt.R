# mvtnorm Genz-Bretz: pmvnorm and pmvt under a seed (the seed argument sets the stream).
#   args: (seed, n, df, maxpts, abseps, releps, lower[n], upper[n], delta[n], corr row-major[n*n], q); +-Inf are +-1e308
#   q 0 value, 1 error, 2 inform (0 normal, 1 error above abseps, 3 not positive semidefinite)
suppressMessages(library(mvtnorm))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("mvt", args, want, rel = 1e-9, abs = 1e-12)
inf2 <- function(x) ifelse(is.infinite(x), sign(x) * 1e308, x)
set.seed(20261118)
rcorr <- function(n) { a <- matrix(rnorm(n * n), n, n); s <- crossprod(a) + diag(runif(n, 0.2, 1)); cov2cor(s) }
for (rep in 1:150) {
  n <- sample(2:7, 1); df <- sample(c(0, 0, 1, 2, 3, 5, 10, 25), 1)
  corr <- rcorr(n); if (rep %% 10 == 0) corr <- diag(n) * 0.5 + 0.5  # exchangeable
  lo <- round(rnorm(n, -1, 1), 2); up <- lo + round(runif(n, 0.2, 3), 2)
  kind <- sample(0:4, n, TRUE)
  lo[kind == 1] <- -Inf; up[kind == 2] <- Inf; lo[kind == 3] <- -Inf; up[kind == 3] <- Inf
  delta <- if (df > 0 && rep %% 3 == 0) round(rnorm(n, 0, 0.5), 2) else rep(0, n)
  if (all(is.infinite(lo) & is.infinite(up))) next
  mp <- sample(c(25000, 1000, 100000), 1); ae <- sample(c(1e-3, 1e-5), 1); re <- sample(c(0, 1e-3), 1)
  seed <- sample(1e6, 1)
  r <- tryCatch(if (df == 0) pmvnorm(lo, up, corr = corr, algorithm = GenzBretz(maxpts = mp, abseps = ae, releps = re), seed = seed)
                else pmvt(lo, up, delta = delta, df = df, corr = corr, algorithm = GenzBretz(maxpts = mp, abseps = ae, releps = re), seed = seed), error = function(e) NULL)
  if (is.null(r)) next
  msg <- attr(r, "msg"); inform <- if (msg == "Normal Completion") 0 else if (grepl("abseps", msg)) 1 else if (grepl("semidef", msg)) 3 else 9
  base <- c(seed, n, df, mp, ae, re, inf2(lo), inf2(up), delta, as.vector(t(corr)))
  add(c(base, 0), as.numeric(r)); add(c(base, 1), attr(r, "error")); add(c(base, 2), inform)
}
emit("mvt", "mvtnorm", list(cases))
