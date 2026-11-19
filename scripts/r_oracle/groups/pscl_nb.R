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
# zero links: zeroinfl and hurdle with Poisson counts and a probit, cloglog or cauchit zero part: "lkll" (log-likelihood) and "lkz" (the zero coefficients weighted by position, 2e-3). Args: (n, p, q, link 1 probit 2 cloglog 3 cauchit, hurdle 0/1, y, x, z).
for (rep in 1:12) {
  n <- sample(250:400, 1); x <- cbind(1, rnorm(n)); z <- cbind(1, rnorm(n)); link <- 1 + (rep - 1) %% 3; hm <- (rep - 1) %/% 3 %% 2
  b <- c(0.7, rnorm(1, 0, .3)); g <- c(-0.5, rnorm(1, 0, .5)); lam <- exp(as.vector(x %*% b)); pz <- plogis(as.vector(z %*% g))
  y <- if (hm == 0) ifelse(runif(n) < pz, 0, rpois(n, lam)) else { yy <- rpois(n, lam); yy[runif(n) < pz] <- 0; yy }
  d <- data.frame(y = y, x1 = x[, 2], z1 = z[, 2]); lk <- c("probit", "cloglog", "cauchit")[link]
  f <- tryCatch(suppressWarnings(if (hm == 0) zeroinfl(y ~ x1 | z1, data = d, link = lk, control = zeroinfl.control(reltol = 1e-12, maxit = 5000)) else hurdle(y ~ x1 | z1, data = d, zero.dist = "binomial", link = lk, control = hurdle.control(reltol = 1e-12, maxit = 5000))), error = function(e) NULL)
  if (is.null(f)) next
  a <- c(n, 2, 2, link, hm, y, as.vector(t(x)), as.vector(t(z))); zc <- coef(f, "zero")
  cases[[length(cases) + 1]] <- case("lkll", a, as.numeric(logLik(f)), rel = 2e-3, abs = 2e-3); cases[[length(cases) + 1]] <- case("lkz", a, sum(zc * 1:2), rel = 5e-3, abs = 5e-3)
}
# zeroinfl with case weights and a count offset (logit zero part): "wol" the log-likelihood, "woc" the count coefficients weighted by position (2e-3). Args: (n, p, q, 0, 0, y, x, z, w, o).
for (rep in 1:8) {
  n <- sample(250:400, 1); x <- cbind(1, rnorm(n)); z <- cbind(1, rnorm(n)); w <- round(runif(n, 0.5, 2), 3); o <- round(runif(n, -0.5, 0.5), 3)
  b <- c(0.7, rnorm(1, 0, .3)); g <- c(-0.5, rnorm(1, 0, .5)); lam <- exp(as.vector(x %*% b) + o); pz <- plogis(as.vector(z %*% g))
  y <- ifelse(runif(n) < pz, 0, rpois(n, lam)); d <- data.frame(y = y, x1 = x[, 2], z1 = z[, 2], w = w, o = o)
  f <- tryCatch(suppressWarnings(zeroinfl(y ~ x1 + offset(o) | z1, data = d, weights = w, control = zeroinfl.control(reltol = 1e-12, maxit = 5000))), error = function(e) NULL)
  if (is.null(f)) next
  a <- c(n, 2, 2, 0, 0, y, as.vector(t(x)), as.vector(t(z)), w, o)
  cases[[length(cases) + 1]] <- case("wol", a, as.numeric(logLik(f)), rel = 2e-3, abs = 2e-3); cases[[length(cases) + 1]] <- case("woc", a, sum(coef(f, "count") * 1:2), rel = 5e-3, abs = 5e-3)
}
emit("pscl_nb", "pscl", list(cases))
