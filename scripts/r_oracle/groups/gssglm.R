# gss gssanova0 (performance-oriented iteration over the exact fit) with cubic marginals. One case per scalar: "gl" (fam, model, method, n, m, X[n*dim], y[n], XO[m*dim], idx),
# fam 1 binomial, 2 poisson, 3 Gamma, 4 inverse.gaussian; model 1 y ~ x1, 2 y ~ x1 + x2, 3 y ~ x1 * x2; method 1 "v", 3 "u"; idx 0 nlambda, 1 score, 2 varht, 3 .. 3 + nq - 1 the theta
# the object carries, the d vector, the iteration count, eta[1:3], w[1:3], then the m predictions and the m standard errors (link scale).
suppressMessages(library(gss))
cases <- list()
add <- function(args, want, tol, ab) cases[[length(cases) + 1]] <<- case("gl", args, want, rel = tol, abs = ab)
nqof <- c(1, 2, 5); n0of <- c(2, 3, 4)
rinvg <- function(n, mu, lambda) {
  nu <- rnorm(n); y <- nu^2; x <- mu + mu^2 * y / (2 * lambda) - mu / (2 * lambda) * sqrt(4 * mu * lambda * y + mu^2 * y^2)
  ifelse(runif(n) <= mu / (mu + x), x, mu^2 / x)
}
run <- function(fam, model, n) {
  dim <- if (model == 1) 1 else 2
  X <- matrix(runif(n * dim, -1, 2), n, dim)
  colnames(X) <- c("x1", "x2")[1:dim]
  df <- as.data.frame(X)
  f <- sin(1.5 * df$x1) * 0.8 + (if (dim == 2) 0.4 * df$x2 else 0)
  y <- switch(fam, rbinom(n, 1, plogis(f * 1.6)), rpois(n, exp(0.5 + f)), rgamma(n, shape = 5, rate = 5 / exp(0.5 + f)), rinvg(n, exp(0.5 + f), 8))
  df$y <- y
  fo <- switch(model, y ~ x1, y ~ x1 + x2, y ~ x1 * x2)
  fm <- c("binomial", "poisson", "Gamma", "inverse.gaussian")[fam]
  method <- if (fam <= 2) 3 else 1
  fit <- tryCatch(suppressWarnings(gssanova0(fo, family = fm, data = df)), error = function(e) NULL)
  if (is.null(fit)) return(invisible(FALSE))
  m <- 5
  xo <- as.data.frame(matrix(runif(m * dim, min(X) + 0.1, max(X) - 0.1), m, dim)); colnames(xo) <- c("x1", "x2")[1:dim]
  for (v in 1:dim) xo[[v]] <- pmin(pmax(xo[[v]], min(X[, v])), max(X[, v]))
  pr <- predict(fit, xo, se.fit = TRUE)
  if (any(!is.finite(pr$se.fit))) return(invisible(FALSE))
  nq <- nqof[model]; n0 <- n0of[model]
  args <- c(fam, model, method, n, m, as.vector(X), y, as.vector(as.matrix(xo)))
  th <- if (nq == 1) 0 else fit$theta
  vals <- c(fit$nlambda, fit$score, fit$varht, th, fit$d, fit$iter, fit$eta[1:3], fit$w[1:3], pr$fit, pr$se.fit)
  # the golden section ends at a 1e-7 bracket and the outer iteration inherits it: nlambda to 1e-5, the rest to 3e-6 relative (measured worst 7e-7)
  nv <- length(vals)
  tol <- rep(3e-6, nv); ab <- rep(1e-9, nv)
  ab[1] <- 1e-5; ab[4:(3 + nq)] <- 1e-4
  tol[3 + nq + n0 + 1] <- 0; ab[3 + nq + n0 + 1] <- 0   # the iteration count is exact
  for (k in seq_along(vals)) add(c(args, k - 1), vals[k], tol[k], ab[k])
  invisible(TRUE)
}
ok1 <- function(fam, model, lo, hi) { for (t in 1:20) if (!isFALSE(run(fam, model, sample(lo:hi, 1)))) break }
set.seed(20261122)
for (fam in 1:4) for (rep in 1:2) ok1(fam, 1, 50, 80)
for (fam in 1:4) ok1(fam, 2, 60, 90)
for (fam in 1:4) ok1(fam, 3, 60, 90)
emit("gssglm", "gss", list(cases))
