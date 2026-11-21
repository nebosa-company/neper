# gss ssanova0 (exact RKPACK fit) with cubic marginals. One case per scalar of a fit: "ss" (model, method, n, varht, m, X[n*dim], y[n], XO[m*dim], idx), model 1 y ~ x1, 2 y ~ x1 + x2,
# 3 y ~ x1 * x2; method 1 "v", 2 "m", 3 "u"; idx 0 nlambda, 1 score, 2 varht, 3 .. 3 + nq - 1 theta, then the d vector, then the m predictions, then the m standard errors.
suppressMessages(library(gss))
cases <- list()
add <- function(args, want, tol, ab = 1e-9) cases[[length(cases) + 1]] <<- case("ss", args, want, rel = tol, abs = ab)
nqof <- c(1, 2, 5, 1, 2, 5, 1); n0of <- c(2, 3, 4, 2, 3, 4, 3)
run <- function(model, method, n, varht) {
  dim <- if (model %in% c(1, 4)) 1 else 2
  X <- matrix(runif(n * dim, -1, 2), n, dim)
  colnames(X) <- c("x1", "x2")[1:dim]
  df <- as.data.frame(X)
  y <- sin(2 * df$x1) + (if (dim == 2) 0.5 * df$x2 + df$x1 * df$x2 * 0.3 else 0) + rnorm(n, 0, 0.3)
  df$y <- y
  fo <- switch((model - 1) %% 3 + 1, y ~ x1, y ~ x1 + x2, y ~ x1 * x2)
  tp <- if (model >= 4 && model <= 6) list(x1 = "tp", x2 = "tp") else NULL
  if (model == 7) { fo <- y ~ x; df$x <- X }
  mc <- c("v", "m", "u")[method]
  fit <- tryCatch(ssanova0(fo, type = tp, data = df, method = mc, varht = varht), error = function(e) NULL)
  if (is.null(fit)) return(invisible(FALSE))
  m <- 6
  xo <- as.data.frame(matrix(runif(m * dim, min(X) + 0.1, max(X) - 0.1), m, dim)); colnames(xo) <- c("x1", "x2")[1:dim]
  for (v in 1:dim) xo[[v]] <- pmin(pmax(xo[[v]], min(X[, v])), max(X[, v]))
  xn <- xo; if (model == 7) xn <- data.frame(x = I(as.matrix(xo)))
  pr <- predict(fit, xn, se.fit = TRUE)
  nq <- nqof[model]; n0 <- n0of[model]
  args <- c(model, method, n, varht, m, as.vector(X), y, as.vector(as.matrix(xo)))
  th <- if (nq == 1) 0 else fit$theta
  vals <- c(fit$nlambda, fit$score, fit$varht, th, fit$d, pr$fit, pr$se.fit)
  # the golden section search stops at a bracket of 1e-7 in log10(n lambda) and its last comparisons are decided by rounding noise, so nlambda is compared to 1e-6 absolute (rel 1e-6 of the value or 1e-6 below it)
  # and what depends on it to 1e-6 relative; the score is flat there and agrees to 1e-9
  tol <- c(1e-6, 1e-9, 1e-6, rep(1e-5, nq), rep(1e-6, n0), rep(1e-6, m), rep(1e-6, m))
  # nlambda below -10 is an interpolating fit: the score is flat to rounding noise there and the golden section ends anywhere along it
  ab <- c(if (fit$nlambda < -10) 1e-2 else if (model %in% c(3, 6)) 1e-5 else 1e-6, 1e-9, 1e-9, rep(1e-5, nq), rep(1e-9, n0 + 2 * m))
  for (k in seq_along(vals)) add(c(args, k - 1), vals[k], tol[k], ab[k])
  invisible(TRUE)
}
set.seed(20261121)
ok1 <- function(model, mt, lo, hi) { for (t in 1:20) if (!isFALSE(run(model, mt, sample(lo:hi, 1), 0.09))) break }
for (rep in 1:4) for (mt in 1:3) ok1(1, mt, 15, 30)
for (rep in 1:2) for (mt in 1:3) ok1(2, mt, 25, 35)
for (rep in 1:2) for (mt in 1:3) ok1(3, mt, 30, 40)
for (rep in 1:2) for (mt in 1:3) ok1(4, mt, 15, 30)
for (rep in 1:2) for (mt in 1:3) ok1(5, mt, 25, 35)
for (rep in 1:2) for (mt in 1:3) ok1(6, mt, 30, 40)
for (rep in 1:3) for (mt in 1:3) ok1(7, mt, 25, 40)
emit("gss", "gss", list(cases))
