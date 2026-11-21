# gss ssden (cubic marginals, sampled id.basis). One case per scalar: "sd" (model, n, nb, seed, skip, ng, m, X[n*dim], XO[m*dim], idx),
# model 1 ~ x1, 2 ~ x1 + x2, 3 ~ x1 * x2; the quadrature is gauss.quad(200) in one dimension and the tensor grid gauss.quad(ng) per variable in two (passed as quad=);
# id.basis is sample(n, nb) after set.seed(seed); idx 0 lambda, 1 .. nq theta, then c (nb), d, int, cv, the m densities, nb and the id.basis checksums.
suppressMessages(library(gss))
cases <- list()
add <- function(args, want, tol, ab) cases[[length(cases) + 1]] <<- case("sd", args, want, rel = tol, abs = ab)
nqof <- c(1, 2, 5); n0of <- c(1, 2, 3)
run <- function(model, n, seed, skip, ng) {
  dim <- if (model == 1) 1 else 2
  x1 <- c(rnorm(n %/% 2, -1, 0.7), rnorm(n - n %/% 2, 1.2, 0.9))
  X <- matrix(x1, n, 1)
  if (dim == 2) X <- cbind(x1, 0.5 * x1 + rnorm(n, 0, 0.8))
  colnames(X) <- c("x1", "x2")[1:dim]
  df <- as.data.frame(X)
  fo <- switch(model, ~x1, ~x1 + x2, ~x1 * x2)
  nb <- max(30, ceiling(10 * n^(2/9))); if (nb >= n) nb <- n
  dom <- apply(X, 2, function(v) range(v) + c(-1, 1) * diff(range(v)) * 0.05)
  quad <- NULL
  if (dim == 2) {
    q1 <- gauss.quad(ng, dom[, 1]); q2 <- gauss.quad(ng, dom[, 2])
    pt <- expand.grid(x1 = q1$pt, x2 = q2$pt)
    quad <- list(pt = pt, wt = as.vector(outer(q1$wt, q2$wt)))
  }
  fit <- tryCatch(suppressWarnings(ssden(fo, data = df, seed = seed, quad = quad, skip.iter = skip > 0)), error = function(e) NULL)
  if (is.null(fit)) return(invisible(FALSE))
  m <- 6
  xo <- as.data.frame(sapply(1:dim, function(v) runif(m, min(X[, v]), max(X[, v])))); colnames(xo) <- colnames(X)
  pr <- dssden(fit, if (dim == 1) xo[[1]] else xo)
  nq <- nqof[model]; n0 <- n0of[model]; idb <- fit$id.basis
  args <- c(model, n, nb, seed, skip, ng, m, as.vector(X), as.vector(as.matrix(xo)))
  vals <- c(fit$lambda, fit$theta, fit$c, fit$d, fit$int, fit$cv, pr, nb, sum(idb), sum(idb * seq_along(idb)), idb[1], idb[nb])
  nv <- length(vals)
  tol <- rep(1e-6, nv); ab <- rep(1e-9, nv)
  ab[1] <- 1e-3
  # the nlm search over several theta ends where the cross-validation score is flat to its own Newton precision (prec 1e-7): theta to 0.1, the fit to 5e-2 relative
  if (nq > 1 && skip == 0) { tol[] <- 5e-2; ab[] <- 0.02; ab[2:(1 + nq)] <- 0.1; ab[1] <- 1e-3 }
  tol[(nv - 4):nv] <- 0; ab[(nv - 4):nv] <- 0
  for (k in seq_along(vals)) add(c(args, k - 1), vals[k], tol[k], ab[k])
  invisible(TRUE)
}
set.seed(20261124)
for (n in c(90, 140, 200)) for (t in 1:10) if (!isFALSE(run(1, n, 100 + n + t, 0, 0))) break
for (model in 2:3) for (t in 1:10) if (!isFALSE(run(model, 120, 500 + model * 10 + t, 1, 14))) break
for (t in 1:10) if (!isFALSE(run(2, 110, 700 + t, 0, 14))) break
emit("gssden", "gss", list(cases))
