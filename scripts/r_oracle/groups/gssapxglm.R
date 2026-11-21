# gss gssanova1 (the performance-oriented iteration over the sampled basis; gssanova itself minimises a cross-validation of the Kullback-Leibler score and is not ported) with cubic marginals. One case per scalar: "ag" (fam, model, method, n, nb, m, seed, skip, X[n*dim], y[n], XO[m*dim], idx),
# fam 1 binomial, 2 poisson, 3 Gamma, 4 inverse.gaussian; model 1 y ~ x1, 2 y ~ x1 + x2, 3 y ~ x1 * x2; method 1 "u", 2 "v" (the family default); id.basis is sample(n, nb) after set.seed(seed);
# idx 0 nlambda, 1 score, 2 varht, 3 .. 3 + nq - 1 theta, then d, eta[1:3], w[1:3], the m predictions and standard errors (link scale), nb and the id.basis checksums.
suppressMessages(library(gss))
cases <- list()
add <- function(args, want, tol, ab) cases[[length(cases) + 1]] <<- case("ag", args, want, rel = tol, abs = ab)
nqof <- c(1, 2, 5); n0of <- c(2, 3, 4)
rinvg <- function(n, mu, lambda) {
  nu <- rnorm(n); y <- nu^2; x <- mu + mu^2 * y / (2 * lambda) - mu / (2 * lambda) * sqrt(4 * mu * lambda * y + mu^2 * y^2)
  ifelse(runif(n) <= mu / (mu + x), x, mu^2 / x)
}
run <- function(fam, model, n, seed, skip) {
  dim <- if (model == 1) 1 else 2
  X <- matrix(runif(n * dim, -1, 2), n, dim)
  colnames(X) <- c("x1", "x2")[1:dim]
  df <- as.data.frame(X)
  f <- sin(1.5 * df$x1) * 0.8 + (if (dim == 2) 0.4 * df$x2 else 0)
  y <- switch(fam, rbinom(n, 1, plogis(f * 1.6)), rpois(n, exp(0.5 + f)), rgamma(n, shape = 5, rate = 5 / exp(0.5 + f)), rinvg(n, exp(0.5 + f), 8))
  df$y <- y
  fo <- switch(model, y ~ x1, y ~ x1 + x2, y ~ x1 * x2)
  fm <- c("binomial", "poisson", "Gamma", "inverse.gaussian")[fam]
  method <- if (fam <= 2) 1 else 2
  nb <- max(30, ceiling(10 * n^(2/9))); if (nb >= n) nb <- n
  fit <- tryCatch(suppressWarnings(gssanova1(fo, family = fm, data = df, seed = seed, skip.iter = skip > 0)), error = function(e) NULL)
  if (is.null(fit)) return(invisible(FALSE))
  m <- 5
  xo <- as.data.frame(matrix(runif(m * dim, min(X) + 0.1, max(X) - 0.1), m, dim)); colnames(xo) <- c("x1", "x2")[1:dim]
  for (v in 1:dim) xo[[v]] <- pmin(pmax(xo[[v]], min(X[, v])), max(X[, v]))
  pr <- predict(fit, xo, se.fit = TRUE)
  if (any(!is.finite(pr$se.fit))) return(invisible(FALSE))
  nq <- nqof[model]; n0 <- n0of[model]; idb <- fit$id.basis
  args <- c(fam, model, method, n, nb, m, seed, skip, as.vector(X), y, as.vector(as.matrix(xo)))
  vals <- c(fit$nlambda, fit$score, fit$varht, fit$theta, fit$d, fit$eta[1:3], fit$w[1:3], pr$fit, pr$se.fit, nb, sum(idb), sum(idb * seq_along(idb)), idb[1], idb[nb])
  nv <- length(vals)
  tol <- rep(1e-6, nv); ab <- rep(1e-9, nv)
  ab[1] <- 1e-4; ab[4:(3 + nq)] <- 1e-4
  # the iteration count is exact; the id.basis checksums are exact

  tol[(nv - 4):nv] <- 0; ab[(nv - 4):nv] <- 0
  # the nlm search over several theta ends where the score is flat to rounding noise
  if (nq > 1 && skip == 0) { tol[] <- 5e-2; ab[] <- 0.02; ab[4:(3 + nq)] <- 0.1; ab[1] <- 1e-3; tol[(nv - 4):nv] <- 0; ab[(nv - 4):nv] <- 0 }
  for (k in seq_along(vals)) add(c(args, k - 1), vals[k], tol[k], ab[k])
  invisible(TRUE)
}
ok1 <- function(fam, model, lo, hi, skip = 0) { for (t in 1:20) { n <- sample(lo:hi, 1); if (!isFALSE(run(fam, model, n, 1000 + sample(1e4, 1), skip))) break } }
set.seed(20261126)
for (fam in 1:4) for (rep in 1:2) ok1(fam, 1, 50, 90)
for (fam in 1:4) ok1(fam, 2, 60, 90, 1)
for (fam in 1:4) ok1(fam, 3, 60, 90, 1)
for (fam in c(1, 3)) ok1(fam, 2, 60, 90, 0)
emit("gssapxglm", "gss", list(cases))
