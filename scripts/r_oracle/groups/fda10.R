# fda, register.fd with periodic = TRUE (a shift is fitted), Fourier curves; crit 1 and 2.
#   (ynb, nw, lambda, ncurve, which, index, crit, ycoefs[ynb ncurve], y0coefs[ynb]); which 0 regfd coefficients, 1 Wfd coefficients, 2 warpfd coefficients, 3 shift
# Wfd coefficients: rel 1e-7 (the line search is flat near the optimum and its last step amplifies rounding by about 4e-9); everything else 1e-9.
suppressMessages(library(fda))
cases <- list()
set.seed(20261207)
for (rep in 1:6) {
  nw <- sample(4:5, 1); lam <- 10^sample(-3:0, 1); ynb <- sample(c(7, 9), 1); ncurve <- sample(2:3, 1); crit <- if (rep %% 2 == 0) 1 else 2
  ybasis <- create.fourier.basis(c(0, 1), ynb); x <- seq(0, 1, length = 101)
  ys <- sapply(1:ncurve, function(i) { s <- runif(1, -0.08, 0.08); a <- runif(1, -0.03, 0.03); u <- x + s + a * sin(2 * pi * x); sin(2 * pi * u) + 0.5 * cos(4 * pi * u) })
  yfd <- smooth.basis(x, ys, fdPar(ybasis, 2, 1e-8))$fd
  y0 <- sin(2 * pi * x) + 0.5 * cos(4 * pi * x); y0fd <- smooth.basis(x, y0, fdPar(ybasis, 2, 1e-8))$fd
  wbasis <- create.bspline.basis(c(0, 1), nw); WfdPar <- fdPar(fd(matrix(0, nw, 1), wbasis), 2, lam)
  reg <- NULL; invisible(capture.output(reg <- suppressWarnings(register.fd(y0fd, yfd, WfdPar, dbglev = 0, periodic = TRUE, crit = crit))))
  outs <- list(reg$regfd$coefs, reg$Wfd$coefs, reg$warpfd$coefs, reg$shift)
  for (w in 0:3) { v <- as.vector(outs[[w + 1]]); for (q in seq_along(v)) cases[[length(cases) + 1]] <- case("r", c(ynb, nw, lam, ncurve, w, q - 1, crit, as.vector(yfd$coefs), as.vector(y0fd$coefs)), v[q], rel = if (w == 1) 1e-7 else 1e-9, abs = if (w == 1) 1e-9 else 1e-10) }
}
emit("fda10", "fda", list(cases))
