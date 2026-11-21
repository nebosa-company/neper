# gss ssanova (approximate basis, nlm0 for one smoothing parameter and nlm over theta for several). One case per scalar: "ap" (model, method, alpha, n, nb, m, seed, X[n*dim], y[n], idb[nb], XO[m*dim], idx),
# model as in the gss group (1-3 cubic, 4-6 thin-plate marginals, 7 a two-dimensional thin-plate), method 1 "u" (varht 1), 2 "v", 3 "m" (GML); seed > 0: id.basis is sample(n, nb) after set.seed(seed) (idb is then ignored),
# otherwise idb (1-based) is given; idx 0 nlambda, 1 score, 2 varht, 3 .. 3 + nq - 1 theta, then the d vector, then the m predictions and the m standard errors (predict se.fit).
suppressMessages(library(gss))
cases <- list()
add <- function(args, want, tol, ab) cases[[length(cases) + 1]] <<- case("ap", args, want, rel = tol, abs = ab)
nqof <- c(1, 2, 5, 1, 2, 5, 1); n0of <- c(2, 3, 4, 2, 3, 4, 3)
run <- function(model, method, alpha, n, nb, skip) {
  dim <- if (model %in% c(1, 4)) 1 else 2
  X <- matrix(runif(n * dim, -1, 2), n, dim)
  colnames(X) <- c("x1", "x2")[1:dim]
  df <- as.data.frame(X)
  y <- sin(2 * df$x1) + (if (dim == 2) 0.5 * df$x2 + df$x1 * df$x2 * 0.3 else 0) + rnorm(n, 0, 0.3)
  df$y <- y
  fo <- switch((model - 1) %% 3 + 1, y ~ x1, y ~ x1 + x2, y ~ x1 * x2)
  tp <- if (model >= 4 && model <= 6) list(x1 = "tp", x2 = "tp") else NULL
  if (model == 7) { fo <- y ~ x; df$x <- X }
  mc <- c("u", "v", "m")[method]
  idb <- sort(sample(n, nb))
  # skip >= 2 is a seed: id.basis is what ssanova draws itself (nbasis from its default rule, set.seed(skip), sample(n, nbasis)) and is compared too, unsorted
  if (skip >= 2) {
    fit <- tryCatch(suppressWarnings(ssanova(fo, type = tp, data = df, method = mc, alpha = alpha, varht = 0.09, seed = skip)), error = function(e) NULL)
    if (!is.null(fit)) { idb <- fit$id.basis; nb <- length(idb) }
  } else
  fit <- tryCatch(suppressWarnings(ssanova(fo, type = tp, data = df, method = mc, alpha = alpha, varht = 0.09, id.basis = idb, skip.iter = skip > 0)), error = function(e) NULL)
  if (is.null(fit)) return(invisible(FALSE))
  m <- 6
  xo <- as.data.frame(matrix(runif(m * dim, min(X) + 0.1, max(X) - 0.1), m, dim)); colnames(xo) <- c("x1", "x2")[1:dim]
  for (v in 1:dim) xo[[v]] <- pmin(pmax(xo[[v]], min(X[, v])), max(X[, v]))
  xn <- xo; if (model == 7) xn <- data.frame(x = I(as.matrix(xo)))
  pr <- predict(fit, xn, se.fit = TRUE)
  nq <- nqof[model]; n0 <- n0of[model]
  args <- c(model, method, alpha, n, nb, m, skip, as.vector(X), y, idb, as.vector(as.matrix(xo)))
  vals <- c(fit$nlambda, fit$score, fit$varht, fit$theta, fit$d, pr$fit, pr$se.fit, if (skip >= 2) c(nb, sum(idb), sum(idb * seq_along(idb)), idb[1], idb[nb]))
  nv <- length(vals)
  # nlm0 and the fits at a given theta are deterministic to the 1e-7 bracket of the search (nlambda 1e-4 absolute, the rest 1e-7); the nlm search over several theta ends along flat
  # directions where rounding noise (10^x from another libm) picks the path: there theta is compared to 0.05 and the rest to 3e-3 relative
  tol <- rep(1e-7, nv); ab <- rep(1e-9, nv)
  ab[1] <- 1e-4; ab[4:(3 + nq)] <- if (nq > 1 && skip == 0) 0.05 else 1e-9
  if (nq > 1 && skip == 0) { tol[2:nv] <- 3e-3; fl <- which(fit$theta < -5); if (length(fl)) ab[3 + fl] <- 2 }   # a theta below -5 is a term switched off: its size is noise
  # GML (method 3) is a flat score: nlm0 stops on a 1e-6 relative neighbour of R's point, and the nlm search over several theta wanders (theta 0.3, rest 5e-2 relative)
  if (method == 3) { tol[] <- 1e-3; if (nq > 1 && skip == 0) { tol[2:nv] <- 5e-2; ab[4:(3 + nq)] <- 0.3; fl <- which(fit$theta < -5); if (length(fl)) ab[3 + fl] <- 2 } }
  for (k in seq_along(vals)) add(c(args, k - 1), vals[k], tol[k], ab[k])
  invisible(TRUE)
}
ok1 <- function(model, method, alpha, lo, hi, skip = 0) { for (t in 1:20) { n <- sample(lo:hi, 1); if (!isFALSE(run(model, method, alpha, n, 30, skip))) break } }
set.seed(20261123)
for (model in c(1, 4)) for (mt in 1:2) for (al in c(1, 1.4)) ok1(model, mt, al, 40, 70)
for (model in c(2, 5, 7)) for (mt in 1:2) ok1(model, mt, 1.4, 40, 65)
for (model in c(3, 6)) for (mt in 1:2) ok1(model, mt, 1.4, 45, 70)
for (model in c(2, 3, 5, 6)) for (mt in 1:2) ok1(model, mt, 1.4, 40, 60, 1)
for (mt in 1:2) { set.seed(900 + mt); run(1, mt, 1.4, 150, 30, 4000 + mt) }
for (model in 1:7) ok1(model, 3, 1.4, 40, 60)
for (model in c(2, 5)) ok1(model, 3, 1.4, 40, 60, 1)
set.seed(910); run(1, 3, 1.4, 150, 30, 4003)
emit("gssapx", "gss", list(cases))
