# gss ssanova with an approximate basis, fits that carry no optimiser: writes tests/oracle/gssfix.json and tests/oracle/gssskip.json (one run emits both).
# One case per scalar: "ap" (model, method, alpha, n, nb, m, mode, X[n*dim], y[n], idb[nb], XO[m*dim], [nlambda, theta[nq] when mode 2], idx),
# model as in the gssapx group (1-3 cubic, 4-6 thin-plate marginals, 7 a two-dimensional thin-plate), method 1 "u" (varht 1), 2 "v", 3 "m" (GML).
# mode 2 (gssfix): R's own search ran, and its converged nlambda and theta are the inputs: the fit is then one least-squares problem and equals R at 1e-9,
#   where the searches (nlm0, nlm over theta) stop on rounding-dependent points; idx 0 score, 1 varht, then the d vector, the m predictions and the m standard errors.
# mode 1 (gssskip): skip.iter = TRUE, the starting-theta fit of ssanova (nlm0 for lambda only); idx as in gssapx: 0 nlambda, 1 score, 2 varht, 3 .. theta, d, predictions, se.
suppressMessages(library(gss))
fixed <- list(); skipc <- list()
nqof <- c(1, 2, 5, 1, 2, 5, 1); n0of <- c(2, 3, 4, 2, 3, 4, 3)
run <- function(model, method, alpha, n, nb, mode) {
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
  fit <- tryCatch(suppressWarnings(ssanova(fo, type = tp, data = df, method = mc, alpha = alpha, varht = 0.09, id.basis = idb, skip.iter = mode == 1)), error = function(e) NULL)
  if (is.null(fit)) return(invisible(FALSE))
  m <- 6
  xo <- as.data.frame(matrix(runif(m * dim, min(X) + 0.1, max(X) - 0.1), m, dim)); colnames(xo) <- c("x1", "x2")[1:dim]
  for (v in 1:dim) xo[[v]] <- pmin(pmax(xo[[v]], min(X[, v])), max(X[, v]))
  xn <- xo; if (model == 7) xn <- data.frame(x = I(as.matrix(xo)))
  pr <- predict(fit, xn, se.fit = TRUE)
  nq <- nqof[model]
  args <- c(model, method, alpha, n, nb, m, mode, as.vector(X), y, idb, as.vector(as.matrix(xo)), if (mode == 2) c(fit$nlambda, fit$theta))
  if (mode == 2) {
    vals <- c(fit$score, fit$varht, fit$d, pr$fit, pr$se.fit)
    for (k in seq_along(vals)) fixed[[length(fixed) + 1]] <<- case("ap", c(args, k - 1), vals[k], rel = 1e-9, abs = 1e-9)
  } else {
    vals <- c(fit$nlambda, fit$score, fit$varht, fit$theta, fit$d, pr$fit, pr$se.fit)
    nv <- length(vals); tol <- rep(1e-7, nv); ab <- rep(1e-9, nv); ab[1] <- 1e-4
    for (k in seq_along(vals)) skipc[[length(skipc) + 1]] <<- case("ap", c(args, k - 1), vals[k], rel = tol[k], abs = ab[k])
  }
  invisible(TRUE)
}
ok1 <- function(model, method, alpha, lo, hi, mode) { for (t in 1:20) { n <- sample(lo:hi, 1); if (!isFALSE(run(model, method, alpha, n, 30, mode))) break } }
set.seed(20261124)
for (model in 1:7) ok1(model, 3, 1.4, 40, 60, 2)
for (model in c(2, 3, 5, 6)) for (mt in 1:2) ok1(model, mt, 1.4, 40, 60, 2)
for (model in c(2, 3, 5, 6)) for (mt in 1:2) ok1(model, mt, 1.4, 40, 60, 1)
emit("gssfix", "gss", list(fixed))
emit("gssskip", "gss", list(skipc))
