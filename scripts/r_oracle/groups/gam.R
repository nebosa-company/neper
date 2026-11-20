# gam (Hastie): gam(y ~ s(x1, df) + s(x2, df) + z, family) with the package backfitting. Args: (fam 0 gaussian 1 binomial 2 poisson, n, q smooth terms, m extra linear columns, df[q], spar[q], x[q * n], z[m * n], y[n], w[n], what, idx)
# what 0 coef[idx] (intercept, the q smooth linear parts, then the m extras), 1 additive.predictors[idx], 2 fitted.values[idx], 3 smooth[idx] (term-major n), 4 nl.df[idx],
# 17 anova(fit, fit with every df raised by 1.5) second row: idx 0 Df, 1 Deviance, 2 Pr(>Chi), 3 F, 4 Pr(>F) (Gaussian only)
# 12 summary nonparametric row (idx 3 * term + 0 Npar Df, 1 Npar Chisq or F, 2 its p), 13 parametric anova (idx 4 * column + 0 Df, 1 Sum Sq, 2 F, 3 Pr(>F)), 14 idx 0 residual Sum Sq, 1 dispersion, 15 predict se.fit link[idx], 16 predict se.fit response[idx]
# 5 scalar idx 0 deviance 1 null.deviance 2 aic 3 df.residual 4 iter 5 df.null 6 rank, 7 working residuals[idx], 8 nl.chisq[idx], 10 weights[idx], 11 var[idx] (term-major n)
suppressMessages(library(gam))
cases <- list()
set.seed(20261120)
add <- function(args, want, tol = 1e-9) cases[[length(cases) + 1]] <<- case("gam", args, want, rel = tol, abs = 1e-10)
fitcase <- function(fam, x, z, y, w, df, spar, tol = 1e-9) {
  n <- length(y); q <- ncol(x); m <- ncol(z)
  d <- data.frame(y = y, w = w)
  for (j in seq_len(q)) d[[paste0("x", j)]] <- x[, j]
  for (j in seq_len(m)) d[[paste0("z", j)]] <- z[, j]
  terms <- sapply(seq_len(q), function(j) if (df[j] > 0) sprintf("s(x%d, df = %g)", j, df[j]) else sprintf("s(x%d, spar = %g)", j, spar[j]))
  fo <- as.formula(paste("y ~", paste(c(terms, if (m > 0) paste0("z", seq_len(m))), collapse = " + ")))
  f <- gam(fo, family = switch(fam + 1, gaussian, binomial, poisson), data = d, weights = w, control = gam.control(maxit = 30, bf.maxit = 30))
  # df matching leaves spar to Brent's search on a criterion flat to rounding, so a last-bit change of the weights moves some fits by far more than 1e-9: the tolerance is then 20 times that observed move
  mv <- 0
  for (k in 1:4) {
    g <- gam(fo, family = switch(fam + 1, gaussian, binomial, poisson), data = d, weights = w * (1 + c(1e-13, 1e-11, 1e-12, 3e-11)[k] * sin(k * seq_len(n))), control = gam.control(maxit = 30, bf.maxit = 30))
    mv <- max(mv, abs(g$additive.predictors - f$additive.predictors) / (1 + abs(f$additive.predictors)))
  }
  if (mv > 1e-10) tol <- max(tol, 20 * mv)
  hdr <- function(what, idx) c(fam, n, q, m, df, spar,as.vector(x), as.vector(z), y, w, what, idx)
  for (i in seq_along(f$coefficients)) add(hdr(0, i - 1), f$coefficients[i], tol)
  sel <- unique(c(1, n %/% 2, n))
  for (i in sel) { add(hdr(1, i - 1), f$additive.predictors[i], tol); add(hdr(2, i - 1), f$fitted.values[i], tol); add(hdr(7, i - 1), f$residuals[i], tol); if (i == 1) add(hdr(10, i - 1), f$weights[i], tol)
    for (j in seq_len(q)) { add(hdr(3, (j - 1) * n + i - 1), f$smooth[i, j], tol); if (i == n) add(hdr(11, (j - 1) * n + i - 1), f$var[i, j], tol) } }
  sm <- suppressWarnings(summary(f)); an <- sm$anova; pa <- sm$parametric.anova
  for (j in seq_len(q)) for (c in 1:3) add(hdr(12, 3 * (j - 1) + c - 1), an[1 + j, c], tol)
  for (c in seq_len(q + m)) { r <- pa[c, ]; add(hdr(13, 4 * c), r[["Df"]], 0); add(hdr(13, 4 * c + 1), r[["Sum Sq"]], tol); add(hdr(13, 4 * c + 2), r[["F value"]], tol); add(hdr(13, 4 * c + 3), r[["Pr(>F)"]], tol) }
  add(hdr(14, 0), pa["Residuals", "Sum Sq"], tol); add(hdr(14, 1), unname(sm$dispersion), tol)
  df2 <- ifelse(df > 0, df + 1.5, 0)
  terms2 <- sapply(seq_len(q), function(j) if (df2[j] > 0) sprintf("s(x%d, df = %g)", j, df2[j]) else sprintf("s(x%d, spar = %g)", j, spar[j]))
  fo2 <- as.formula(paste("y ~", paste(c(terms2, if (m > 0) paste0("z", seq_len(m))), collapse = " + ")))
  f2 <- gam(fo2, family = switch(fam + 1, gaussian, binomial, poisson), data = d, weights = w, control = gam.control(maxit = 30, bf.maxit = 30))
  if (any(df > 0)) {
  a1 <- suppressWarnings(anova(f, f2, test = "Chisq"))
  add(hdr(17, 0), a1[2, "Df"], tol); add(hdr(17, 1), a1[2, "Deviance"], tol); add(hdr(17, 2), a1[2, "Pr(>Chi)"], tol)
  if (fam == 0) { a2 <- suppressWarnings(anova(f, f2, test = "F")); add(hdr(17, 3), a2[2, "F"], tol); add(hdr(17, 4), a2[2, "Pr(>F)"], tol) }
  }
  pl <- suppressWarnings(predict(f, se.fit = TRUE)); pr <- suppressWarnings(predict(f, type = "response", se.fit = TRUE))
  for (i in unique(c(1, n))) { add(hdr(15, i - 1), pl$se.fit[i], tol); add(hdr(16, i - 1), pr$se.fit[i], tol) }
  for (j in seq_len(q)) { add(hdr(4, j - 1), f$nl.df[j], tol); add(hdr(8, j - 1), f$nl.chisq[j], tol) }
  add(hdr(5, 0), f$deviance, tol); add(hdr(5, 1), f$null.deviance, tol); add(hdr(5, 2), f$aic, tol); add(hdr(5, 3), f$df.residual, tol); add(hdr(5, 4), unlist(f[names(f) == "iter"])[2], 0)
  add(hdr(5, 5), f$df.null, 0); add(hdr(5, 6), f$rank, 0)
}
for (rep in 1:9) {
  fam <- rep %% 3; q <- sample(1:3, 1); m <- sample(0:1, 1); n <- sample(25:38, 1)
  dec <- if (rep %% 5 == 0) 1 else 3
  x <- sapply(seq_len(q), function(j) round(runif(n, -2, 3), dec)); x <- matrix(x, n, q)
  z <- matrix(round(rnorm(n * m), 3), n, m)
  eta <- 0.2 + sin(x[, 1]) * 0.8 + (if (q > 1) 0.3 * x[, 2]^2 / 3 else 0) + (if (m > 0) 0.3 * z[, 1] else 0)
  y <- switch(fam + 1, round(eta + rnorm(n, 0, 0.3), 4), rbinom(n, 1, plogis(eta)), rpois(n, exp(eta)))
  w <- if (rep %% 4 == 1) (if (fam == 1) sample(1:3, n, TRUE) else round(runif(n, 0.5, 2), 3)) else rep(1, n)
  df <- sample(c(2.5, 3, 4, 5), q, replace = TRUE); spar <- rep(1, q)
  if (rep %% 4 == 0) { df[1] <- 0; spar[1] <- sample(c(0.5, 0.8, 1.1), 1) }
  fitcase(fam, x, z, y, w, df, spar)
}
# more than 49 distinct x: the package thins the knots (sknotl); the last has a zero weight and ties
for (rep in 1:3) {
  n <- c(60, 110, 210)[rep]; x <- matrix(round(runif(n, 0, 10), if (rep == 3) 1 else 4), n, 1); z <- matrix(0, n, 0)
  y <- round(sin(x[, 1]) + rnorm(n, 0, 0.4), 4); w <- rep(1, n); if (rep == 3) w[c(5, 77)] <- 0
  fitcase(0, x, z, y, w, 4, 1)
}
emit("gam", "gam", list(cases))
