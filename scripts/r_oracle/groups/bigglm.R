# biglm::bigglm (gaussian, binomial logit, poisson log), run in chunks: coefficients, standard errors, iterations, converged, deviance.
#   args: (fam 0 gaussian 1 binomial 2 poisson, n, p (without the intercept), X[n*p], y[n], w[n], q)  q 0..p coef, p+1..2p+1 se, 2p+2 iterations, 2p+3 converged, 2p+4 deviance
suppressMessages(library(biglm))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-10)
set.seed(20261116)
for (rep in 1:30) {
  fam <- rep %% 3; n <- sample(60:200, 1); p <- sample(1:3, 1)
  X <- matrix(round(rnorm(n * p), 3), n, p); eta <- 0.2 + drop(X %*% c(0.7, -0.5, 0.3)[seq_len(p)])
  y <- switch(fam + 1, round(eta + rnorm(n), 3), rbinom(n, 1, plogis(eta)), rpois(n, exp(eta * 0.6)))
  w <- if (rep %% 2 == 0) round(runif(n, 0.5, 2), 2) else rep(1, n)
  d <- data.frame(y = y, X); names(d) <- c("y", paste0("x", seq_len(p))); d$w <- w
  f <- as.formula(paste("y ~", paste(paste0("x", seq_len(p)), collapse = " + ")))
  fm <- list(gaussian(), binomial(), poisson())[[fam + 1]]
  b <- tryCatch(suppressWarnings(bigglm(f, d, family = fm, weights = ~w, chunksize = 37, quiet = TRUE)), error = function(e) NULL)
  if (is.null(b)) next
  cf <- coef(b); se <- sqrt(diag(vcov(b)))
  out <- c(cf, se, b$iterations, as.numeric(b$converged), b$deviance)
  a <- c(fam, n, p, X, y, w)
  for (q in seq_along(out)) add("bg", c(a, q - 1), out[q])
}
# with an offset: fn "bgo", args (fam, n, p, X, y, w, off, q)
for (rep in 1:30) {
  fam <- rep %% 3; n <- sample(60:200, 1); p <- sample(1:3, 1); off <- round(runif(n, -0.5, 0.5), 3)
  X <- matrix(round(rnorm(n * p), 3), n, p); eta <- 0.2 + drop(X %*% c(0.7, -0.5, 0.3)[seq_len(p)]) + off
  y <- switch(fam + 1, round(eta + rnorm(n), 3), rbinom(n, 1, plogis(eta)), rpois(n, exp(eta * 0.6)))
  w <- if (rep %% 2 == 0) round(runif(n, 0.5, 2), 2) else rep(1, n)
  d <- data.frame(y = y, X); names(d) <- c("y", paste0("x", seq_len(p))); d$w <- w; d$o <- off
  f <- as.formula(paste("y ~", paste(paste0("x", seq_len(p)), collapse = " + "), "+ offset(o)"))
  fm <- list(gaussian(), binomial(), poisson())[[fam + 1]]
  b <- tryCatch(suppressWarnings(bigglm(f, d, family = fm, weights = ~w, chunksize = 37, quiet = TRUE)), error = function(e) NULL)
  if (is.null(b)) next
  cf <- coef(b); se <- sqrt(diag(vcov(b)))
  out <- c(cf, se, b$iterations, as.numeric(b$converged), b$deviance)
  a <- c(fam, n, p, X, y, w, off)
  for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("bgo", c(a, q - 1), out[q], rel = 1e-8, abs = 1e-10)
}
# sandwich standard errors: fn "bgs", args (fam, n, p, X, y, w, q) with q 0 .. p the sandwich se of each coefficient
for (rep in 1:30) {
  fam <- rep %% 3; n <- sample(60:200, 1); p <- sample(1:3, 1)
  X <- matrix(round(rnorm(n * p), 3), n, p); eta <- 0.2 + drop(X %*% c(0.7, -0.5, 0.3)[seq_len(p)])
  y <- switch(fam + 1, round(eta + rnorm(n) * (1 + abs(X[, 1])), 3), rbinom(n, 1, plogis(eta)), rpois(n, exp(eta * 0.6)))
  w <- if (rep %% 2 == 0) round(runif(n, 0.5, 2), 2) else rep(1, n)
  d <- data.frame(y = y, X); names(d) <- c("y", paste0("x", seq_len(p))); d$w <- w
  f <- as.formula(paste("y ~", paste(paste0("x", seq_len(p)), collapse = " + ")))
  fm <- list(gaussian(), binomial(), poisson())[[fam + 1]]
  b <- tryCatch(suppressWarnings(bigglm(f, d, family = fm, weights = ~w, chunksize = 37, quiet = TRUE, sandwich = TRUE)), error = function(e) NULL)
  if (is.null(b)) next
  se <- sqrt(diag(vcov(b))); a <- c(fam, n, p, X, y, w)
  for (q in seq_along(se)) cases[[length(cases) + 1]] <- case("bgs", c(a, q - 1), se[q], rel = 1e-8, abs = 1e-10)
}
# other families and links: fn "bgf", args (fam 3 Gamma(inverse) 4 Gamma(log) 5 gaussian(log) 6 binomial(probit) 7 binomial(cloglog), n, p, X, y, w, q) as bgs without the sandwich
for (rep in 1:40) {
  fam <- 3 + rep %% 5; n <- sample(60:200, 1); p <- sample(1:3, 1)
  X <- matrix(round(runif(n * p, 0.1, 1.2), 3), n, p); eta <- 0.3 + drop(X %*% c(0.5, -0.3, 0.2)[seq_len(p)])
  y <- switch(fam - 2, round(rgamma(n, 4, 4 * eta), 4), round(rgamma(n, 3, 3 / exp(eta)), 4), round(exp(eta) + rnorm(n, 0, 0.3), 4), rbinom(n, 1, pnorm(eta - 0.5)), rbinom(n, 1, 1 - exp(-exp(eta - 0.8))))
  w <- if (rep %% 2 == 0) round(runif(n, 0.5, 2), 2) else rep(1, n)
  d <- data.frame(y = y, X); names(d) <- c("y", paste0("x", seq_len(p))); d$w <- w
  f <- as.formula(paste("y ~", paste(paste0("x", seq_len(p)), collapse = " + ")))
  fm <- list(Gamma(), Gamma(link = "log"), gaussian(link = "log"), binomial(link = "probit"), binomial(link = "cloglog"))[[fam - 2]]
  b <- tryCatch(suppressWarnings(bigglm(f, d, family = fm, weights = ~w, chunksize = 37, quiet = TRUE)), error = function(e) NULL)
  if (is.null(b)) next
  cf <- coef(b); se <- sqrt(diag(vcov(b)))
  if (!all(is.finite(c(cf, se, b$deviance)))) next
  out <- c(cf, se, b$iterations, as.numeric(b$converged), b$deviance)
  a <- c(fam, n, p, X, y, w)
  for (q in seq_along(out)) cases[[length(cases) + 1]] <- case("bgf", c(a, q - 1), out[q], rel = 1e-7, abs = 1e-9)
}
emit("bigglm", "biglm", list(cases))
