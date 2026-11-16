# mvtnorm TVPACK trivariate: pmvnorm and pmvt over (-Inf, h], any correlation matrix.
#   args: (nu, h1, h2, h3, r21, r31, r32, eps); nu 0 is the normal
suppressMessages(library(mvtnorm))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("tvpack", args, want, rel = 1e-8, abs = 1e-10)
set.seed(20261120)
rcorr <- function(n) { a <- matrix(rnorm(n * n), n, n); s <- crossprod(a) + diag(runif(n, 0.05, 1)); cov2cor(s) }
for (rep in 1:200) {
  nu <- sample(c(0, 0, 1, 2, 3, 4, 5, 8, 15), 1)
  corr <- rcorr(3)
  if (rep %% 11 == 0) corr[1, 2] <- corr[2, 1] <- 0
  if (rep %% 13 == 0) { corr[2, 3] <- corr[3, 2] <- 0.999999999999 }
  h <- round(rnorm(3, 0.3, 1.2), 2)
  if (rep %% 17 == 0) h <- c(0, 0, 0)
  eps <- sample(c(1e-6, 1e-8, 1e-3), 1)
  alg <- TVPACK(abseps = eps)
  r <- tryCatch(if (nu == 0) pmvnorm(upper = h, corr = corr, algorithm = alg) else pmvt(upper = h, df = nu, corr = corr, algorithm = alg), error = function(e) NULL)
  if (is.null(r)) next
  add(c(nu, h, corr[2, 1], corr[3, 1], corr[3, 2], eps), as.numeric(r))
}
emit("tvpack", "mvtnorm", list(cases))
