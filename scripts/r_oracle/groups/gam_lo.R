# gam (Hastie): gam(y ~ lo(x1, span, degree) + ... + z, family) with the package loess smoother. Args: (fam 0 gaussian 1 binomial 2 poisson, n, q lo terms, m extra linear columns, span[q], degree[q], x[q * n], z[m * n], y[n], w[n], what, idx)
# what as in the gam group: 0 coef (intercept, then the model-matrix columns of the lo terms (degree columns each), then the m extras), 1 additive.predictors, 2 fitted.values, 3 smooth (term-major n), 4 nl.df, 5 scalars, 7 working residuals, 8 nl.chisq, 10 weights, 11 var (term-major n),
# 12 summary nonparametric rows (3 * term + 0 Npar Df, 1 Npar Chisq or F, 2 its p), 13 parametric anova (4 * term-or-extra ordinal c from 1: 0 Df, 1 Sum Sq, 2 F, 3 Pr(>F)), 14 residual Sum Sq and dispersion, 15/16 predict se.fit link/response,
# 17 anova(fit, fit with every span raised by 0.15): idx 0 Df, 1 Deviance, 2 Pr(>Chi), 3 F, 4 Pr(>F) (Gaussian only)
suppressMessages(library(gam))
cases <- list()
set.seed(20261122)
add <- function(args, want, tol = 1e-9) cases[[length(cases) + 1]] <<- case("gam_lo", args, want, rel = tol, abs = 1e-10)
fitcase <- function(fam, x, z, y, w, span, degree, tol = 1e-9) {
  n <- length(y); q <- ncol(x); m <- ncol(z)
  d <- data.frame(y = y, w = w)
  for (j in seq_len(q)) d[[paste0("x", j)]] <- x[, j]
  for (j in seq_len(m)) d[[paste0("z", j)]] <- z[, j]
  mk <- function(sp) as.formula(paste("y ~", paste(c(sprintf("lo(x%d, span = %g, degree = %d)", seq_len(q), sp, degree), if (m > 0) paste0("z", seq_len(m))), collapse = " + ")))
  famf <- switch(fam + 1, gaussian, binomial, poisson)
  ctl <- gam.control(maxit = 30, bf.maxit = 30)
  f <- gam(mk(span), family = famf, data = d, weights = w, control = ctl)
  hdr <- function(what, idx) c(fam, n, q, m, span, degree, as.vector(x), as.vector(z), y, w, what, idx)
  for (i in seq_along(f$coefficients)) add(hdr(0, i - 1), f$coefficients[i], tol)
  sel <- unique(c(1, n %/% 2, n))
  for (i in sel) { add(hdr(1, i - 1), f$additive.predictors[i], tol); add(hdr(2, i - 1), f$fitted.values[i], tol); add(hdr(7, i - 1), f$residuals[i], tol); if (i == 1) add(hdr(10, i - 1), f$weights[i], tol)
    for (j in seq_len(q)) { add(hdr(3, (j - 1) * n + i - 1), f$smooth[i, j], tol); if (i == n) add(hdr(11, (j - 1) * n + i - 1), f$var[i, j], tol) } }
  sm <- suppressWarnings(summary(f)); an <- sm$anova; pa <- sm$parametric.anova
  for (j in seq_len(q)) for (c in 1:3) add(hdr(12, 3 * (j - 1) + c - 1), an[1 + j, c], tol)
  for (c in seq_len(q + m)) { r <- pa[c, ]; add(hdr(13, 4 * c), r[["Df"]], 0); add(hdr(13, 4 * c + 1), r[["Sum Sq"]], tol); add(hdr(13, 4 * c + 2), r[["F value"]], tol); add(hdr(13, 4 * c + 3), r[["Pr(>F)"]], tol) }
  add(hdr(14, 0), pa["Residuals", "Sum Sq"], tol); add(hdr(14, 1), unname(sm$dispersion), tol)
  f2 <- gam(mk(round(pmin(span + 0.15, 1), 2)), family = famf, data = d, weights = w, control = ctl)
  a1 <- suppressWarnings(anova(f, f2, test = "Chisq"))
  add(hdr(17, 0), a1[2, "Df"], tol); add(hdr(17, 1), a1[2, "Deviance"], tol); add(hdr(17, 2), a1[2, "Pr(>Chi)"], tol)
  if (fam == 0) { a2 <- suppressWarnings(anova(f, f2, test = "F")); add(hdr(17, 3), a2[2, "F"], tol); add(hdr(17, 4), a2[2, "Pr(>F)"], tol) }
  pl <- suppressWarnings(predict(f, se.fit = TRUE)); pr <- suppressWarnings(predict(f, type = "response", se.fit = TRUE))
  for (i in unique(c(1, n))) { add(hdr(15, i - 1), pl$se.fit[i], tol); add(hdr(16, i - 1), pr$se.fit[i], tol) }
  for (j in seq_len(q)) { add(hdr(4, j - 1), f$nl.df[j], tol); add(hdr(8, j - 1), f$nl.chisq[j], tol) }
  add(hdr(5, 0), f$deviance, tol); add(hdr(5, 1), f$null.deviance, tol); add(hdr(5, 2), f$aic, tol); add(hdr(5, 3), f$df.residual, tol); add(hdr(5, 4), unlist(f[names(f) == "iter"])[2], 0)
  add(hdr(5, 5), f$df.null, 0); add(hdr(5, 6), f$rank, 0)
}
for (rep in 1:10) {
  fam <- rep %% 3; q <- sample(1:2, 1); m <- sample(0:1, 1); n <- sample(25:38, 1)
  x <- matrix(round(runif(n * q, -2, 3), 3), n, q)
  z <- matrix(round(rnorm(n * m), 3), n, m)
  eta <- 0.2 + sin(x[, 1]) * 0.8 + (if (q > 1) 0.3 * x[, 2]^2 / 3 else 0) + (if (m > 0) 0.3 * z[, 1] else 0)
  y <- switch(fam + 1, round(eta + rnorm(n, 0, 0.3), 4), rbinom(n, 1, plogis(eta)), rpois(n, exp(eta)))
  w <- if (rep %% 4 == 1) (if (fam == 1) sample(1:3, n, TRUE) else round(runif(n, 0.5, 2), 3)) else rep(1, n)
  span <- sample(c(0.5, 0.65, 0.8, 0.9), q, replace = TRUE); degree <- sample(1:2, q, replace = TRUE); if (q == 1) degree <- 1
  fitcase(fam, x, z, y, w, span, degree)
}
# ties in x, a zero weight, and more unique x
for (rep in 1:3) {
  n <- c(45, 70, 100)[rep]; x <- matrix(round(runif(n, 0, 10), c(4, 1, 4)[rep]), n, 1); z <- matrix(0, n, 0)
  y <- round(sin(x[, 1]) + rnorm(n, 0, 0.4), 4); w <- rep(1, n); if (rep == 2) w[c(5, 17)] <- 0
  fitcase(0, x, z, y, w, c(0.4, 0.6, 0.3)[rep], c(1, 1, 1)[rep])
}
emit("gam_lo", "gam", list(cases))
