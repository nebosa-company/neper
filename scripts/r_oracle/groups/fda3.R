# fda, smooth.morph and landmarkreg (the slow cases).
#   p   smooth.morph            (nw, lambda, m, lo, hi, ylo, yhi, nobs, which, c0[nw], x[nobs], y[nobs]); which < nw a coefficient, nw f, nw + 1 gradient norm, nw + 2 iterations
#   l   landmarkreg             (nbasis, ncurve, nl, ylambda, which, index, x0marks[nl], ximarks[ncurve nl] by curve, coefs[nbasis ncurve]); which 0 regfd, 1 warpfd, 2 warpinvfd, 3 Wfd coefficients
suppressMessages(library(fda))
cases <- list()
set.seed(20261204)
# smooth.morph
for (rep in 1:10) {
  nw <- sample(5:8, 1); lo <- runif(1, 0, 1); hi <- lo + runif(1, 1, 3); ylo <- lo; yhi <- hi; lam <- 10^sample(-8:-3, 1); m <- 2
  wb <- create.bspline.basis(c(lo, hi), nw); c0 <- rnorm(nw, 0, 0.3)
  nl <- sample(2:4, 1); xi <- sort(runif(nl, lo + 0.1 * (hi - lo), hi - 0.1 * (hi - lo))); yi <- sort(xi + rnorm(nl, 0, 0.05 * (hi - lo)))
  x <- c(lo, xi, hi); y <- c(lo, yi, hi); nobs <- length(x)
  fit <- suppressWarnings(smooth.morph(x, y, c(ylo, yhi), fdPar(fd(matrix(c0, nw, 1), wb), m, lam)))
  out <- c(as.vector(fit$Wfdobj$coefs), fit$f, fit$norm, fit$iternum)
  for (w in seq_along(out)) cases[[length(cases) + 1]] <- case("p", c(nw, lam, m, lo, hi, ylo, yhi, nobs, w - 1, c0, x, y), out[w], rel = 1e-8, abs = 1e-10)
}
# landmarkreg
for (rep in 1:6) {
  nbasis <- sample(6:9, 1); ncurve <- sample(2:4, 1); nl <- sample(2:3, 1); yl <- 10^sample(-10:-8, 1)
  x0 <- sort(runif(nl, 0.15, 0.85)); if (any(diff(c(0, x0, 1)) < 0.12)) x0 <- seq(0.2, 0.8, length.out = nl)
  xim <- t(sapply(1:ncurve, function(i) sort(pmin(pmax(x0 + rnorm(nl, 0, 0.04), 0.05), 0.95))))
  if (nl == 1) xim <- matrix(xim, ncurve, 1)
  basis <- create.bspline.basis(c(0, 1), nbasis); cf <- matrix(rnorm(nbasis * ncurve), nbasis, ncurve)
  # the two smooth.morph fits landmarkreg makes for the first curve, as "p" cases: the warping function and its inverse
  nbs <- nl + 2; Wb <- create.bspline.basis(c(0, 1), nbs); nfine <- min(101, 10 * nbasis); xfine <- seq(0, 1, length = nfine); c00 <- rep(0, nbs)
  xv <- c(0, x0, 1); yv <- c(0, xim[1, ], 1)
  fit1 <- smooth.morph(xv, yv, c(0, 1), fdPar(fd(matrix(0, nbs, 1), Wb), 2, 1e-10)); out1 <- c(as.vector(fit1$Wfdobj$coefs), fit1$f, fit1$norm, fit1$iternum)
  for (w in seq_along(out1)) cases[[length(cases) + 1]] <- case("p", c(nbs, 1e-10, 2, 0, 1, 0, 1, length(xv), w - 1, c00, xv, yv), out1[w], rel = 1e-8, abs = 1e-10)
  hf <- monfn(xfine, fit1$Wfdobj); b <- 1 / (hf[nfine] - hf[1]); hf <- (0 - b * hf[1]) + b * hf; hf[c(1, nfine)] <- c(0, 1)
  fit2 <- smooth.morph(hf, xfine, c(0, 1), fdPar(fd(matrix(0, nbs, 1), Wb), 2, 1e-10)); out2 <- c(as.vector(fit2$Wfdobj$coefs), fit2$f, fit2$norm, fit2$iternum)
  for (w in seq_along(out2)) cases[[length(cases) + 1]] <- case("p", c(nbs, 1e-10, 2, 0, 1, 0, 1, nfine, w - 1, c00, hf, xfine), out2[w], rel = 1e-8, abs = 1e-10)
  res <- NULL; invisible(capture.output(res <- suppressWarnings(landmarkreg(fd(cf, basis), xim, x0, c(0, 1), ylambda = yl))))
  outs <- list(res$regfd$coefs, res$warpfd$coefs, res$warpinvfd$coefs, res$Wfd$coefs)
  for (w in 0:3) { v <- as.vector(outs[[w + 1]]); for (q in seq_along(v)) cases[[length(cases) + 1]] <- case("l", c(nbasis, ncurve, nl, yl, w, q - 1, x0, as.vector(t(xim)), cf), v[q], rel = 1e-7, abs = 1e-9) }
}
emit("fda3", "fda", list(cases))
