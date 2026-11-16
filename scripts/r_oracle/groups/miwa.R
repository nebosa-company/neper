# mvtnorm Miwa: pmvnorm on a correlation matrix with algorithm = Miwa(steps).
#   args: (n, steps, lower[n], upper[n], corr row-major[n*n]); +-Inf are +-1e308
suppressMessages(library(mvtnorm))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("miwa", args, want, rel = 1e-8, abs = 1e-10)
inf2 <- function(x) ifelse(is.infinite(x), sign(x) * 1e308, x)
set.seed(20261121)
rcorr <- function(n) { a <- matrix(rnorm(n * n), n, n); s <- crossprod(a) + diag(runif(n, 0.3, 1)); cov2cor(s) }
for (rep in 1:120) {
  n <- sample(2:6, 1); steps <- sample(c(16, 64, 128, 256), 1)
  corr <- rcorr(n)
  if (rep %% 9 == 0) corr[1, 2] <- corr[2, 1] <- 0
  lo <- round(rnorm(n, -1, 1), 2); up <- lo + round(runif(n, 0.2, 3), 2)
  kind <- sample(0:4, n, TRUE)
  lo[kind == 1] <- -Inf; up[kind == 2] <- Inf; lo[kind == 3] <- -Inf; up[kind == 3] <- Inf
  if (rep %% 7 == 0) { lo <- rep(-Inf, n); up <- round(rnorm(n, 0.5, 1), 2) }
  if (rep %% 8 == 0) { up <- rep(Inf, n); lo <- round(rnorm(n, -0.5, 1), 2) }
  r <- tryCatch(suppressWarnings(pmvnorm(lo, up, corr = corr, algorithm = Miwa(steps = steps))), error = function(e) NULL)
  if (is.null(r)) next
  add(c(n, steps, inf2(lo), inf2(up), as.vector(t(corr))), as.numeric(r))
}
emit("miwa", "mvtnorm", list(cases))
