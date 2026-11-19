# arm: logit, invlogit, se.coef of a linear model, binned.resids.
# bayesglm: see the block before emit.
#   args: "logit"/"invlogit" (v); "se" (n, p, x row-major n by p, y) with the coefficient index last; "binned" (nclass, n, x, y, column, bin) weighted by position over the table
suppressMessages(library(arm))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-11)
set.seed(20262000)
for (v in c(0.01, 0.2, 0.5, 0.77, 0.999)) add("logit", c(v), logit(v))
for (v in c(-12, -3, -0.4, 0, 1.3, 8, 30)) add("invlogit", c(v), invlogit(v))
for (rep in 1:15) {
  n <- sample(20:60, 1); p <- sample(2:4, 1); x <- matrix(round(rnorm(n * p), 4), n, p); x[, 1] <- 1; y <- round(rnorm(n, x %*% rnorm(p)), 4)
  fit <- lm(y ~ x - 1); se <- se.coef(fit)
  for (j in 1:p) add("se", c(n, p, as.vector(t(x)), y, j - 1), se[j])
}
for (rep in 1:25) {
  n <- sample(30:120, 1); nclass <- sample(c(0, 3, 4, 6, 10), 1); if (nclass == 0) nclass <- floor(sqrt(n))
  x <- if (rep %% 2 == 0) round(rnorm(n), 1) else round(rnorm(n), 5); y <- round(rnorm(n), 4)
  bn <- binned.resids(x, y, nclass)$binned
  for (b in seq_len(nrow(bn))) for (cc in 1:6) add("binned", c(nclass, n, x, y, cc - 1, b - 1), bn[b, cc])
  add("binned_rows", c(nclass, n, x, y, 0, 0), nrow(bn))
}
# "rescale" (mode, n, x, index): numeric and two-valued inputs under each binary.inputs mode
modes <- c("center", "0/1", "-0.5,0.5", "full")
for (rep in 1:24) {
  n <- sample(5:30, 1); x <- if (rep %% 2 == 0) round(rnorm(n, 3, 2), 3) else sample(c(0, 1), n, TRUE)
  if (length(unique(x)) < 2) x[1:2] <- c(0, 1)
  m <- sample(1:4, 1); r <- rescale(x, modes[m])
  for (j in 1:n) add("rescale", c(m - 1, n, x, j - 1), r[j])
}
# standardize(lm): "stdlm" args (n, q, y, x row-major without the intercept, index): coefficient index (0 the intercept)
for (rep in 1:15) {
  n <- sample(25:80, 1); q <- sample(2:4, 1); Xm <- matrix(round(rnorm(n * q, 1, 2), 3), n, q)
  if (q >= 3) Xm[, 3] <- rbinom(n, 1, 0.4)
  y <- round(as.vector(cbind(1, Xm) %*% runif(q + 1, -1, 1)) + rnorm(n), 3)
  dfx <- as.data.frame(Xm); names(dfx) <- paste0("v", 1:q); dfx$y <- y
  assign("dfx_g", dfx, envir = globalenv()); assign("fo_g", as.formula(paste("y ~", paste(names(dfx)[1:q], collapse = " + "))), envir = globalenv())
  m <- lm(fo_g, data = dfx_g)
  sm <- standardize(m); cf <- as.numeric(coef(sm))
  for (j in 0:q) cases[[length(cases) + 1]] <- case("stdlm", c(n, q, y, as.vector(t(Xm)), j), cf[j + 1], rel = 1e-8, abs = 1e-11)
}
# bayesglm: args (n, k, family 0 gaussian 1 binomial 2 poisson, x[n * k] row-major with the constant first, y[n], j): coefficient j (0-based) of bayesglm with the default priors.
for (rep in 1:18) {
  fam <- (rep - 1) %% 3; n <- sample(60:150, 1); k <- sample(2:4, 1)
  X <- cbind(1, matrix(round(rnorm(n * (k - 1)), 4), n)); if (k >= 3 && rep %% 2 == 0) X[, 3] <- rbinom(n, 1, 0.4)
  b <- c(0.2, runif(k - 1, -0.8, 0.8)); eta <- as.vector(X %*% b)
  y <- if (fam == 0) round(eta + rnorm(n, 0, 0.6), 4) else if (fam == 1) rbinom(n, 1, plogis(eta)) else rpois(n, exp(eta))
  d <- data.frame(y = y, X[, -1, drop = FALSE]); names(d) <- c("y", paste0("v", seq_len(k - 1)))
  f <- tryCatch(suppressWarnings(bayesglm(y ~ ., data = d, family = list(gaussian, binomial, poisson)[[fam + 1]])), error = function(e) NULL)
  if (is.null(f)) next
  for (j in 0:(k - 1)) cases[[length(cases) + 1]] <- case("bayesglm", c(n, k, fam, as.vector(t(X)), y, j), unname(coef(f))[j + 1], rel = 1e-6, abs = 1e-8)
}
# bayesglm2: the same with prior.df and prior.scale given: args (n, k, family, x, y, j, prior.df, prior.scale).
for (rep in 1:18) {
  fam <- (rep - 1) %% 3; n <- sample(60:150, 1); k <- sample(2:4, 1)
  pdf <- c(Inf, 4, 7)[(rep - 1) %/% 3 %% 3 + 1]; psc <- c(1, 2.5)[rep %% 2 + 1]
  X <- cbind(1, matrix(round(rnorm(n * (k - 1)), 4), n)); b <- c(0.2, runif(k - 1, -0.8, 0.8)); eta <- as.vector(X %*% b)
  y <- if (fam == 0) round(eta + rnorm(n, 0, 0.6), 4) else if (fam == 1) rbinom(n, 1, plogis(eta)) else rpois(n, exp(eta))
  d <- data.frame(y = y, X[, -1, drop = FALSE]); names(d) <- c("y", paste0("v", seq_len(k - 1)))
  f <- tryCatch(suppressWarnings(bayesglm(y ~ ., data = d, family = list(gaussian, binomial, poisson)[[fam + 1]], prior.df = pdf, prior.scale = psc)), error = function(e) NULL)
  if (is.null(f)) next
  for (j in 0:(k - 1)) cases[[length(cases) + 1]] <- case("bayesglm2", c(n, k, fam, as.vector(t(X)), y, j, pdf, psc), unname(coef(f))[j + 1], rel = 1e-6, abs = 1e-8)
}
# bayesglm2 with the probit link (family code 3): the default prior scales are 4 and 16 (2.5 and 10 times 1.6); the arguments carry prior.df and 4.
for (rep in 1:9) {
  n <- sample(80:160, 1); k <- sample(2:4, 1); pdf <- c(1, Inf, 5)[rep %% 3 + 1]
  X <- cbind(1, matrix(round(rnorm(n * (k - 1)), 4), n)); b <- c(0.2, runif(k - 1, -0.8, 0.8)); y <- rbinom(n, 1, pnorm(as.vector(X %*% b)))
  d <- data.frame(y = y, X[, -1, drop = FALSE]); names(d) <- c("y", paste0("v", seq_len(k - 1)))
  f <- tryCatch(suppressWarnings(bayesglm(y ~ ., data = d, family = binomial(link = "probit"), prior.df = pdf)), error = function(e) NULL)
  if (is.null(f)) next
  for (j in 0:(k - 1)) cases[[length(cases) + 1]] <- case("bayesglm2", c(n, k, 3, as.vector(t(X)), y, j, pdf, 4), unname(coef(f))[j + 1], rel = 1e-6, abs = 1e-8)
}
# bayesglm2 with the cloglog link (family code 4), default prior scale 2.5 and 10
for (rep in 1:9) {
  n <- sample(100:200, 1); k <- sample(2:4, 1); pdf <- c(1, Inf, 5)[rep %% 3 + 1]
  X <- cbind(1, matrix(round(rnorm(n * (k - 1)), 4), n)); b <- c(-0.5, runif(k - 1, -0.6, 0.6)); y <- rbinom(n, 1, 1 - exp(-exp(as.vector(X %*% b))))
  d <- data.frame(y = y, X[, -1, drop = FALSE]); names(d) <- c("y", paste0("v", seq_len(k - 1)))
  f <- tryCatch(suppressWarnings(bayesglm(y ~ ., data = d, family = binomial(link = "cloglog"), prior.df = pdf)), error = function(e) NULL)
  if (is.null(f)) next
  for (j in 0:(k - 1)) cases[[length(cases) + 1]] <- case("bayesglm2", c(n, k, 4, as.vector(t(X)), y, j, pdf, 2.5), unname(coef(f))[j + 1], rel = 1e-6, abs = 1e-8)
}
# bayesglm3: per-coefficient prior mean, df and scale (the full vectors, the intercept first): args (n, k, family, x, y, j, mean[k], df[k], scale[k]).
for (rep in 1:12) {
  fam <- (rep - 1) %% 3; n <- sample(60:150, 1); k <- sample(3:4, 1)
  X <- cbind(1, matrix(round(rnorm(n * (k - 1)), 4), n)); b <- c(0.2, runif(k - 1, -0.8, 0.8)); eta <- as.vector(X %*% b)
  y <- if (fam == 0) round(eta + rnorm(n, 0, 0.6), 4) else if (fam == 1) rbinom(n, 1, plogis(eta)) else rpois(n, exp(eta))
  pm <- round(rnorm(k - 1, 0, 0.5), 3); pd <- sample(c(1, 3, Inf), k - 1, replace = TRUE); psc <- round(runif(k - 1, 0.7, 3), 2)
  d <- data.frame(y = y, X[, -1, drop = FALSE]); names(d) <- c("y", paste0("v", seq_len(k - 1)))
  f <- tryCatch(suppressWarnings(bayesglm(y ~ ., data = d, family = list(gaussian, binomial, poisson)[[fam + 1]], prior.mean = pm, prior.df = pd, prior.scale = psc)), error = function(e) NULL)
  if (is.null(f)) next
  for (j in 0:(k - 1)) cases[[length(cases) + 1]] <- case("bayesglm3", c(n, k, fam, as.vector(t(X)), y, j, c(0, pm), c(1, pd), c(10, psc)), unname(coef(f))[j + 1], rel = 1e-6, abs = 1e-8)
}
emit("arm", "arm", list(cases))
