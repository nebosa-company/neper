# fda, register.fd (crit 2, non-periodic) of B-spline curves toward the mean curve or a given target.
#   (ynb, nw, lambda, ncurve, which, index, ycoefs[ynb ncurve], y0coefs[ynb]); which 0 regfd coefficients, 1 Wfd coefficients, 2 warpfd coefficients
suppressMessages(library(fda))
cases <- list()
set.seed(20261205)
for (rep in 1:6) {
  nw <- sample(4:6, 1); lam <- 10^sample(-3:0, 1); ynb <- sample(11:14, 1); ncurve <- sample(3:5, 1); hast <- rep %% 2 == 0
  ybasis <- create.bspline.basis(c(0, 1), ynb); x <- seq(0, 1, length = 101)
  ys <- sapply(1:ncurve, function(i) { c1 <- runif(1, 0.28, 0.42); c2 <- runif(1, 0.58, 0.72); exp(-((x - c1) / 0.09)^2) + 0.7 * exp(-((x - c2) / 0.09)^2) })
  yfd <- smooth.basis(x, ys, fdPar(ybasis, 2, 1e-6))$fd
  if (hast) { y0 <- exp(-((x - 0.35) / 0.09)^2) + 0.7 * exp(-((x - 0.65) / 0.09)^2); y0fd <- smooth.basis(x, y0, fdPar(ybasis, 2, 1e-6))$fd } else y0fd <- mean.fd(yfd)
  wbasis <- create.bspline.basis(c(0, 1), nw); WfdPar <- fdPar(fd(matrix(0, nw, 1), wbasis), 2, lam)
  reg <- NULL; invisible(capture.output(reg <- suppressWarnings(register.fd(y0fd, yfd, WfdPar, dbglev = 0))))
  outs <- list(reg$regfd$coefs, reg$Wfd$coefs, reg$warpfd$coefs)
  for (w in 0:2) { v <- as.vector(outs[[w + 1]]); for (q in seq_along(v)) cases[[length(cases) + 1]] <- case("r", c(ynb, nw, lam, ncurve, w, q - 1, as.vector(yfd$coefs), as.vector(y0fd$coefs)), v[q], rel = 1e-9, abs = 1e-10) }
}
emit("fda4", "fda", list(cases))
