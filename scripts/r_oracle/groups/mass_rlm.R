# MASS rlm through the formula interface (subset, na.action, factors, weights), summary t values and df, predict.rlm (fit, se.fit, confidence and prediction intervals).
#   "rlmx"  the "rlm" layout then, after the optional weights and init coefficients: m, level, Xnew[m p] col-major; mode 11 t values, 12 summary df[2], 13 fit, 14 se.fit,
#           15 / 16 confidence lwr / upr, 17 / 18 prediction lwr / upr (position-weighted sums)
# MASS rlm.default (M and MM, every psi, scale estimator, init, weights, test.vec) and summary.rlm.
#   "rlm" (seed, n, p, psi 0 huber 1 hampel 2 bisquare, pa, pb, pc, scale.est 0 MAD 1 Huber 2 proposal 2, k2, mm, wt.case, has.weights,
#          init 0 ls 1 lts 2 given, maxit, acc, test.vec 0 resid 1 coef 2 w 3 NULL, lqs nsamp (-9 default), mm.c (0 none), mode,
#          y[n], X[n p] col-major, weights[n] (only when has.weights), initcoef[p] (only when init is 2))
#   mode 0 weighted coef sum, 1 scale, 2 iterations, 3 converged, 4 weights, 5 wresid, 6 residuals, 7 XtX std errors, 8 XtWX std errors, 9 stddev, 10 cov.unscaled
suppressMessages(library(MASS))
cases <- list()
add <- function(args, want, rel = 1e-8, abs = 1e-9) if (length(want) == 1 && is.finite(want)) cases[[length(cases) + 1]] <<- case("rlm", args, want, rel = rel, abs = abs)
wsum <- function(v) sum(seq_along(v) * as.numeric(v))
set.seed(20262402)
sest <- c("MAD", "Huber", "proposal 2"); tv <- c("resid", "coef", "w", "NULL")
for (rep in 1:60) {
  n <- sample(c(15, 25, 40), 1); p <- sample(2:4, 1)
  X <- cbind(1, matrix(rnorm(n * (p - 1)), n, p - 1)); b0 <- rnorm(p)
  y <- as.vector(X %*% b0) + rnorm(n) + ifelse(runif(n) < 0.12, rnorm(n, 0, 7), 0)
  wts <- round(runif(n, 0.3, 3), 3); ic <- round(b0 + rnorm(p, 0, 0.3), 4)
  mm <- as.numeric(rep %% 5 == 0)
  psi <- if (mm == 1) 2 else sample(0:2, 1)
  pa <- c(1.345, 2, 4.685)[psi + 1]; pb <- 4; pc <- 8
  if (psi == 0 && rep %% 2 == 0) pa <- 1
  if (psi == 1 && rep %% 3 == 0) { pa <- 1.5; pb <- 3.5; pc <- 7 }
  if (psi == 2 && mm == 0 && rep %% 2 == 0) pa <- 3.5
  se <- if (mm == 1) 0 else sample(0:2, 1); k2 <- if (rep %% 4 == 0) 1.8 else 1.345
  hasw <- as.numeric(rep %% 3 == 1); wc <- as.numeric(hasw == 1 && rep %% 2 == 0)
  init <- if (mm == 1) 0 else sample(0:2, 1, prob = c(.6, .2, .2)); maxit <- c(20, 5, 50)[rep %% 3 + 1]; acc <- c(1e-4, 1e-6)[rep %% 2 + 1]
  tvec <- if (mm == 1) 0 else sample(0:3, 1); nsamp <- if (init == 1 || mm == 1) c(-9, 100)[rep %% 2 + 1] else -9
  mmc <- if (mm == 1 && rep %% 2 == 0) 3 else 0
  seed <- sample(1:1000000, 1)
  args <- list(X, y, method = if (mm == 1) "MM" else "M", maxit = maxit, acc = acc, test.vec = tv[tvec + 1])
  if (mm == 0) {
    args$scale.est <- sest[se + 1]; args$k2 <- k2
    args$psi <- list(psi.huber, psi.hampel, psi.bisquare)[[psi + 1]]
    if (psi == 0) args$k <- pa else if (psi == 1) { args$a <- pa; args$b <- pb; args$c <- pc } else args$c <- pa
    args$init <- if (init == 0) "ls" else if (init == 1) "lts" else ic
  } else if (mmc > 0) args$c <- mmc
  if (hasw == 1) { args$weights <- wts; args$wt.method <- if (wc == 1) "case" else "inv.var" }
  if (!is.na(nsamp) && nsamp != -9) args$lqs.control <- list(nsamp = nsamp)
  if (init == 1 && nsamp == -9) { }
  if (tvec == 3) args["test.vec"] <- list(NULL)
  set.seed(seed)
  f <- tryCatch(suppressWarnings(do.call(rlm, args)), error = function(e) NULL)
  if (is.null(f)) next
  a <- c(seed, n, p, psi, pa, pb, pc, se, k2, mm, wc, hasw, init, maxit, acc, tvec, nsamp, mmc)
  tail <- c(y, as.vector(X), if (hasw == 1) wts, if (init == 2) ic)
  add(c(a, 0, tail), wsum(f$coefficients)); add(c(a, 1, tail), f$s); add(c(a, 2, tail), length(f$conv), 0, 0)
  add(c(a, 3, tail), as.numeric(f$converged), 0, 0); add(c(a, 4, tail), wsum(f$w)); add(c(a, 5, tail), wsum(f$wresid))
  add(c(a, 6, tail), wsum(f$residuals))
  s1 <- tryCatch(suppressWarnings(summary(f, method = "XtX")), error = function(e) NULL)
  s2 <- tryCatch(suppressWarnings(summary(f, method = "XtWX")), error = function(e) NULL)
  if (!is.null(s1)) { add(c(a, 7, tail), wsum(s1$coefficients[, 2])); add(c(a, 9, tail), s1$stddev); add(c(a, 10, tail), wsum(s1$cov.unscaled)) }
  if (!is.null(s2)) add(c(a, 8, tail), wsum(s2$coefficients[, 2]))
}

addx <- function(args, want, rel = 1e-8, abs = 1e-9) if (length(want) == 1 && is.finite(want)) cases[[length(cases) + 1]] <<- case("rlmx", args, want, rel = rel, abs = abs)
for (rep in 1:18) {
  n <- sample(c(20, 28, 36), 1)
  d <- data.frame(a = round(rnorm(n), 3), b = round(runif(n), 3), g = factor(sample(c("u", "v", "w"), n, TRUE)))
  d$y <- round(1 + d$a - 0.7 * d$b + 0.5 * (d$g == "v") + rnorm(n) + ifelse(runif(n) < 0.12, rnorm(n, 0, 6), 0), 4)
  d$a[sample(n, 2)] <- NA; d$y[sample(n, 1)] <- NA
  assign("d", d, globalenv()); w <- round(runif(n, 0.4, 2.5), 3); assign("w", w, globalenv())
  idx <- sort(sample(n, n - 5)); mm <- as.numeric(rep %% 3 == 0); hasw <- as.numeric(rep %% 2 == 0)
  fo <- list(y ~ a, y ~ a + g, y ~ a + b + g, y ~ a * b)[[(rep - 1) %% 4 + 1]]
  seed <- sample(1:1000000, 1)
  args <- list(fo, data = d, subset = idx, na.action = na.omit, method = if (mm == 1) "MM" else "M")
  if (hasw == 1) args$weights <- w
  set.seed(seed)
  f <- tryCatch(suppressWarnings(do.call(rlm, args)), error = function(e) NULL)
  if (is.null(f)) next
  X <- model.matrix(f); nn <- nrow(X); p <- ncol(X); y <- as.vector(f$fitted.values + f$residuals); wts <- if (hasw == 1) f$weights else NULL
  nd <- data.frame(a = round(rnorm(4), 3), b = round(runif(4), 3), g = factor(sample(c("u", "v", "w"), 4, TRUE), levels = levels(d$g)))
  Xn <- model.matrix(delete.response(terms(f)), nd, xlev = f$xlevels); m <- nrow(Xn); lev <- c(0.95, 0.9, 0.99)[rep %% 3 + 1]
  psi <- if (mm == 1) 2 else 0; pa <- if (mm == 1) 4.685 else 1.345
  a <- c(seed, nn, p, psi, pa, 4, 8, 0, 1.345, mm, 0, hasw, 0, 20, 1e-4, 0, -9, 0)
  tail <- c(y, as.vector(X), wts, m, lev, as.vector(Xn))
  s1 <- suppressWarnings(summary(f))
  addx(c(a, 0, tail), wsum(f$coefficients)); addx(c(a, 1, tail), f$s); addx(c(a, 6, tail), wsum(f$residuals))
  addx(c(a, 11, tail), wsum(s1$coefficients[, 3])); addx(c(a, 12, tail), s1$df[2], 0, 0)
  p0 <- suppressWarnings(predict(f, nd, se.fit = TRUE))
  addx(c(a, 13, tail), wsum(p0$fit)); addx(c(a, 14, tail), wsum(p0$se.fit))
  pc <- suppressWarnings(predict(f, nd, interval = "confidence", level = lev)); pp <- suppressWarnings(predict(f, nd, interval = "prediction", level = lev))
  addx(c(a, 15, tail), wsum(pc[, 2])); addx(c(a, 16, tail), wsum(pc[, 3])); addx(c(a, 17, tail), wsum(pp[, 2])); addx(c(a, 18, tail), wsum(pp[, 3]))
}
emit("mass_rlm", "MASS", list(cases))
