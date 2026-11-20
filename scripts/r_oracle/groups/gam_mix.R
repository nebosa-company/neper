# gam (Hastie) with s() and lo() terms together (the package general.wam backfitting, smoothers in the order s() first, then lo()).
# Args: (fam 0 gaussian 1 binomial 2 poisson, n, q smooth terms in formula order, m extra linear columns, kind[q] (0 s, 1 lo), p1[q] (df of s, span of lo), p2[q] (spar of s when df = 0, degree of lo), x[q * n], z[m * n], y[n], w[n], what, idx)
# what: 0 coef (formula order: intercept, the columns of each smooth term, then the m extras), 1 additive.predictors, 2 fitted.values, 3 smooth (term-major n, the s terms first, then the lo terms), 4 nl.df, 5 scalars (0 deviance 1 null.deviance 2 aic 3 df.residual 4 iter 5 df.null 6 rank),
# 7 working residuals, 8 nl.chisq, 9 bf.iter[idx], 10 weights, 11 var, 12 summary nonparametric rows (3 * j + 0 Npar Df, 1 Npar Chisq or F, 2 its p), 13 parametric anova (4 * term ordinal c from 1 in formula order: 0 Df, 1 Sum Sq, 2 F, 3 Pr(>F)), 14 residual Sum Sq and dispersion,
# 15/16 predict se.fit link/response, 17 anova(fit, fit with every df raised by 1.5 and span lowered by 0.15): idx 0 Df, 1 Deviance, 2 Pr(>Chi), 3 F, 4 Pr(>F) (Gaussian only)
suppressMessages(library(gam))
cases <- list()
set.seed(20261125)
add <- function(args, want, tol = 1e-9) cases[[length(cases) + 1]] <<- case("gam_mix", args, want, rel = tol, abs = 1e-10)
fitcase <- function(fam, x, z, y, w, kind, p1, p2, tol = 1e-9) {
  n <- length(y); q <- ncol(x); m <- ncol(z); if (Sys.getenv("GAM_DEBUG") != "") message("CASE fam=", fam, " n=", n, " q=", q, " m=", m, " kind=", paste(kind, collapse=","), " p1=", paste(p1, collapse=","), " p2=", paste(p2, collapse=","))
  d <- data.frame(y = y, w = w)
  for (j in seq_len(q)) d[[paste0("x", j)]] <- x[, j]
  for (j in seq_len(m)) d[[paste0("z", j)]] <- z[, j]
  mk <- function(a1) {
    terms <- sapply(seq_len(q), function(j) if (kind[j] == 1) sprintf("lo(x%d, span = %g, degree = %d)", j, if (a1) round(p1[j] - 0.15, 2) else p1[j], p2[j]) else if (p1[j] > 0) sprintf("s(x%d, df = %g)", j, if (a1) p1[j] + 1.5 else p1[j]) else sprintf("s(x%d, spar = %g)", j, p2[j]))
    as.formula(paste("y ~", paste(c(terms, if (m > 0) paste0("z", seq_len(m))), collapse = " + ")))
  }
  famf <- switch(fam + 1, gaussian, binomial, poisson)
  ctl <- gam.control(maxit = 30, bf.maxit = 30)
  f <- gam(mk(FALSE), family = famf, data = d, weights = w, control = ctl)
# df matching leaves spar to Brent's search on a criterion flat to rounding, so a last-bit change of the weights moves the s() fits by far more than 1e-9: the tolerance is then 100 times that observed move mv <- 0 if (any(kind == 0 & p1 > 0)) for (k in 1:4) { g <- gam(mk(FALSE), family = famf, data = d, weights = w * (1 + c(1e-13, 1e-11, 1e-12, 3e-11)[k] * sin(k * seq_len(n))), control = ctl) mv <- max(mv, abs(g$additive.predictors - f$additive.predictors) / (1 + abs(f$additive.predictors))) }
  mv <- 0; f2 <- gam(mk(TRUE), family = famf, data = d, weights = w, control = ctl)
  if (any(kind == 0 & p1 > 0)) for (k in 1:4) {
    g <- gam(mk(FALSE), family = famf, data = d, weights = w * (1 + c(1e-13, 1e-11, 1e-12, 3e-11)[k] * sin(k * seq_len(n))), control = ctl)
    u <- c(f$additive.predictors, f$residuals, f$nl.chisq, f$nl.df, f$deviance); v <- c(g$additive.predictors, g$residuals, g$nl.chisq, g$nl.df, g$deviance)
    g2 <- gam(mk(TRUE), family = famf, data = d, weights = w * (1 + c(1e-13, 1e-11, 1e-12, 3e-11)[k] * sin(k * seq_len(n))), control = ctl); u <- c(u, f2$additive.predictors, f2$deviance); v <- c(v, g2$additive.predictors, g2$deviance)
    mv <- max(mv, abs(v - u) / (1 + abs(u)))
  }
  if (mv > 1e-10) tol <- max(tol, 100 * mv)
  hdr <- function(what, idx) c(fam, n, q, m, kind, p1, p2, as.vector(x), as.vector(z), y, w, what, idx)
  for (i in seq_along(f$coefficients)) add(hdr(0, i - 1), f$coefficients[i], tol)
  sel <- unique(c(1, n %/% 2, n))
  for (i in sel) { add(hdr(1, i - 1), f$additive.predictors[i], tol); add(hdr(2, i - 1), f$fitted.values[i], tol); add(hdr(7, i - 1), f$residuals[i], tol); if (i == 1) add(hdr(10, i - 1), f$weights[i], tol)
    for (j in seq_len(q)) { add(hdr(3, (j - 1) * n + i - 1), f$smooth[i, j], tol); if (i == n) add(hdr(11, (j - 1) * n + i - 1), f$var[i, j], tol) } }
  sm <- suppressWarnings(summary(f)); an <- sm$anova; pa <- sm$parametric.anova
  for (j in seq_len(q)) for (c in 1:3) add(hdr(12, 3 * (j - 1) + c - 1), an[colnames(f$smooth)[j], c], tol)
  for (c in seq_len(q + m)) { r <- pa[c, ]; add(hdr(13, 4 * c), r[["Df"]], 0); add(hdr(13, 4 * c + 1), r[["Sum Sq"]], tol); add(hdr(13, 4 * c + 2), r[["F value"]], tol); add(hdr(13, 4 * c + 3), r[["Pr(>F)"]], tol) }
  add(hdr(14, 0), pa["Residuals", "Sum Sq"], tol); add(hdr(14, 1), unname(sm$dispersion), tol)
  a1 <- suppressWarnings(anova(f, f2, test = "Chisq"))
  add(hdr(17, 0), a1[2, "Df"], tol); add(hdr(17, 1), a1[2, "Deviance"], tol); add(hdr(17, 2), a1[2, "Pr(>Chi)"], tol)
  if (fam == 0) { a2 <- suppressWarnings(anova(f, f2, test = "F")); add(hdr(17, 3), a2[2, "F"], tol); add(hdr(17, 4), a2[2, "Pr(>F)"], tol) }
  pl <- suppressWarnings(predict(f, se.fit = TRUE)); pr <- suppressWarnings(predict(f, type = "response", se.fit = TRUE))
  for (i in unique(c(1, n))) { add(hdr(15, i - 1), pl$se.fit[i], tol); add(hdr(16, i - 1), pr$se.fit[i], tol) }
  for (j in seq_len(q)) { add(hdr(4, j - 1), f$nl.df[j], tol); add(hdr(8, j - 1), f$nl.chisq[j], tol) }
  for (j in seq_along(f$bf.iter)) add(hdr(9, j - 1), f$bf.iter[j], 0)
  add(hdr(5, 0), f$deviance, tol); add(hdr(5, 1), f$null.deviance, tol); add(hdr(5, 2), f$aic, tol); add(hdr(5, 3), f$df.residual, tol); add(hdr(5, 4), unlist(f[names(f) == "iter"])[2], 0)
  add(hdr(5, 5), f$df.null, 0); add(hdr(5, 6), f$rank, 0)
}
# The package Fortran corrupts memory now and then (a segfault, often cases later), so every case runs in its own R process and a crashed one is skipped.
if (nzchar(Sys.getenv("GAM_CHILD"))) {
  do.call(fitcase, readRDS(Sys.getenv("GAM_CHILD")))
  saveRDS(cases, Sys.getenv("GAM_OUT"))
  quit(save = "no")
}
runcase <- function(...) {
  tf <- tempfile(fileext = ".rds"); of <- tempfile(fileext = ".rds")
  saveRDS(list(...), tf)
  Sys.setenv(GAM_CHILD = tf, GAM_OUT = of)
  suppressWarnings(system2(file.path(R.home("bin"), "Rscript"), c("scripts/r_oracle/generate.R", "gam_mix"), stdout = FALSE, stderr = FALSE))
  Sys.unsetenv(c("GAM_CHILD", "GAM_OUT"))
  if (file.exists(of)) cases <<- c(cases, readRDS(of)) else message("a case crashed in the package and is skipped")
}
for (rep in 1:12) {
  fam <- rep %% 3; q <- sample(2:3, 1); m <- sample(0:1, 1); n <- sample(25:38, 1)
  x <- matrix(round(runif(n * q, -2, 3), 3), n, q)
  z <- matrix(round(rnorm(n * m), 3), n, m)
  eta <- 0.2 + sin(x[, 1]) * 0.8 + 0.3 * x[, 2]^2 / 3 + (if (m > 0) 0.3 * z[, 1] else 0)
  y <- switch(fam + 1, round(eta + rnorm(n, 0, 0.3), 4), rbinom(n, 1, plogis(eta)), rpois(n, exp(eta)))
  w <- if (rep %% 4 == 1) (if (fam == 1) sample(1:3, n, TRUE) else round(runif(n, 0.5, 2), 3)) else rep(1, n)
  kind <- rep(0, q); kind[sample(q, sample(1:(q - 1), 1))] <- 1
  p1 <- ifelse(kind == 1, sample(c(0.5, 0.65, 0.8, 0.9), q, replace = TRUE), sample(c(2.5, 3, 4), q, replace = TRUE))
  p2 <- ifelse(kind == 1, sample(1:2, q, replace = TRUE), 1); if (fam != 0 || sum(kind) > 1) p2[kind == 1] <- 1
  if (rep %% 5 == 0 && any(kind == 0)) { j <- which(kind == 0)[1]; p1[j] <- 0; p2[j] <- 0.8 }
  runcase(fam = fam, x = x, z = z, y = y, w = w, kind = kind, p1 = p1, p2 = p2)
}
emit("gam_mix", "gam", list(cases))
