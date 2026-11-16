# rms rcspline.eval, ols and lrm with a restricted cubic spline term of explicit knots plus one linear covariate.
#   args: (n, nk, knots[nk], x[n], z[n], y[n])  (y binary for lrm, continuous for ols)
#   fn: "rcs" (basis weighted by position), "lrm_coef" "lrm_lr" "lrm_c" "lrm_dxy" "lrm_r2" "lrm_brier", "ols_coef" "ols_se" "ols_r2" "ols_sigma"
suppressMessages(library(rms))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-6, abs = 1e-8)
ws <- function(v) sum(as.vector(v) * seq_along(v))
set.seed(20261222)
for (rep in 1:24) {
  n <- sample(60:200, 1); nk <- sample(3:5, 1)
  x <- rnorm(n); z <- rnorm(n); yb <- rbinom(n, 1, plogis(0.6 * x - z + 0.3 * x^2)); yc <- 1 + x - 0.5 * x^2 + z + rnorm(n)
  knots <- as.numeric(quantile(x, seq(0.1, 0.9, length.out = nk), type = 7))
  d <- data.frame(x, z, yb, yc)
  basis <- rcspline.eval(x, knots = knots, inclx = TRUE, norm = 2)
  a <- c(n, nk, knots, x, z, rep(0, n))
  ab <- c(n, nk, knots, x, z, yb); ac <- c(n, nk, knots, x, z, yc)
  add("rcs", a, ws(t(basis)))
  fl <- tryCatch(lrm(yb ~ rcs(x, knots) + z, d, tol = 1e-14, maxit = 100), error = function(e) NULL)
  if (!is.null(fl) && !any(!is.finite(coef(fl)))) {
    s <- fl$stats
    add("lrm_coef", ab, ws(coef(fl))); add("lrm_lr", ab, s[["Model L.R."]]); add("lrm_c", ab, s[["C"]]); add("lrm_dxy", ab, s[["Dxy"]]); add("lrm_r2", ab, s[["R2"]]); add("lrm_brier", ab, s[["Brier"]])
  }
  fo <- ols(yc ~ rcs(x, knots) + z, d)
  add("ols_coef", ac, ws(coef(fo))); add("ols_se", ac, ws(sqrt(diag(vcov(fo))))); add("ols_r2", ac, fo$stats[["R2"]]); add("ols_sigma", ac, fo$stats[["Sigma"]])
}
emit("rms", "rms", list(cases))
