# pscl: zeroinfl with dist = "negbin" (logit zero part): BFGS here, optim in R, so 2e-3. Args: (n, p, q, y[n], x[n * p] row-major with the constant, z[n * q]): "nbll" the log-likelihood, "nbtheta" theta.
suppressMessages(library(pscl))
cases <- list()
set.seed(20262349)
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 2e-3, abs = 2e-3)
for (rep in 1:8) {
  n <- sample(200:300, 1); p <- 2; q <- 2
  x <- cbind(1, rnorm(n)); z <- cbind(1, rnorm(n))
  b <- c(0.8, rnorm(1, 0, .3)); g <- c(-0.7, rnorm(1, 0, .5)); lam <- exp(as.vector(x %*% b)); pz <- plogis(as.vector(z %*% g)); th <- runif(1, 1.5, 5)
  y <- ifelse(runif(n) < pz, 0, rnbinom(n, mu = lam, size = th))
  d <- data.frame(y = y, x1 = x[, 2], z1 = z[, 2])
  f <- tryCatch(suppressWarnings(zeroinfl(y ~ x1 | z1, data = d, dist = "negbin", control = zeroinfl.control(reltol = 1e-12, maxit = 5000))), error = function(e) NULL)
  if (is.null(f) || !is.finite(f$theta) || f$theta > 1e3) next
  a <- c(n, p, q, y, as.vector(t(x)), as.vector(t(z)))
  add("nbll", a, as.numeric(logLik(f))); add("nbtheta", a, f$theta)
}
# hurdle with a negative binomial count: "hnbll" (the total log-likelihood) and "hnbtheta".
for (rep in 1:6) {
  n <- sample(200:300, 1); x <- cbind(1, rnorm(n)); z <- cbind(1, rnorm(n))
  b <- c(0.8, rnorm(1, 0, .3)); g <- c(-0.7, rnorm(1, 0, .5)); lam <- exp(as.vector(x %*% b)); pz <- plogis(as.vector(z %*% g)); th <- runif(1, 1.5, 5)
  y <- rnbinom(n, mu = lam, size = th); y[runif(n) < pz] <- 0
  d <- data.frame(y = y, x1 = x[, 2], z1 = z[, 2])
  f <- tryCatch(suppressWarnings(hurdle(y ~ x1 | z1, data = d, dist = "negbin", control = hurdle.control(reltol = 1e-12, maxit = 5000))), error = function(e) NULL)
  if (is.null(f) || !is.finite(f$theta) || f$theta > 1e3) next
  a <- c(n, 2, 2, y, as.vector(t(x)), as.vector(t(z)))
  add("hnbll", a, as.numeric(logLik(f))); add("hnbtheta", a, f$theta)
}
# geometric counts: "gzll" (zeroinfl) and "ghll" (hurdle) log-likelihoods at 2e-3 relative; "gzc" and "ghc" the count coefficients weighted by position.
for (rep in 1:6) {
  n <- sample(200:300, 1); x <- cbind(1, rnorm(n)); z <- cbind(1, rnorm(n))
  b <- c(0.8, rnorm(1, 0, .3)); g <- c(-0.7, rnorm(1, 0, .5)); lam <- exp(as.vector(x %*% b)); pz <- plogis(as.vector(z %*% g))
  y <- ifelse(runif(n) < pz, 0, rnbinom(n, mu = lam, size = 1)); y2 <- rnbinom(n, mu = lam, size = 1); y2[runif(n) < pz] <- 0
  d <- data.frame(y = y, x1 = x[, 2], z1 = z[, 2]); d2 <- data.frame(y = y2, x1 = x[, 2], z1 = z[, 2])
  f1 <- tryCatch(suppressWarnings(zeroinfl(y ~ x1 | z1, data = d, dist = "geometric", control = zeroinfl.control(reltol = 1e-12, maxit = 5000))), error = function(e) NULL)
  f2 <- tryCatch(suppressWarnings(hurdle(y ~ x1 | z1, data = d2, dist = "geometric", control = hurdle.control(reltol = 1e-12, maxit = 5000))), error = function(e) NULL)
  if (!is.null(f1)) { a <- c(n, 2, 2, y, as.vector(t(x)), as.vector(t(z))); add("gzll", a, as.numeric(logLik(f1))); add("gzc", a, sum(coef(f1, "count") * 1:2)) }
  if (!is.null(f2)) { a <- c(n, 2, 2, y2, as.vector(t(x)), as.vector(t(z))); add("ghll", a, as.numeric(logLik(f2))); add("ghc", a, sum(coef(f2, "count") * 1:2)) }
}
emit("pscl_nb", "pscl", list(cases))
