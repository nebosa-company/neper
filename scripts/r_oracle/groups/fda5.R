# fda: the other bases, a smoothed pca.fd, Fourier smoothing and fRegress with several covariates.
#   mo  monomial basis  (nbasis, lo, hi, deriv, x, j, exponents[nbasis])     ex  exponential basis (nbasis, lo, hi, deriv, x, j, rates[nbasis])
#   po  polygonal basis (n, deriv, x, j, argvals[n])                           k   constant basis (deriv, x)
#   fs  smooth.basis on a Fourier basis (nbasis, period, m, lambda, q, nd, x[nd], y[nd])    fe  eval.fd of a Fourier curve (nbasis, period, deriv, x, coefs[nbasis])
#   Q   pca.fd with harmfdPar lambda > 0 (norder, nb, nrep, m, lambda, index, which 0 value 1 varprop, breaks, coefs)
#   M   fRegress scalar response, intercept + nz scalars + nf functional covariates (norder, nb, N, nf, nz, index, lambdas[nf], breaks, xcoefs[nf nbasis N], zs[nz N], y[N])
suppressMessages(library(fda))
cases <- list()
set.seed(20261205)
for (rep in 1:10) {
  nbs <- sample(2:6, 1); ex <- sort(sample(0:7, nbs)); lo <- runif(1, 0, 1); hi <- lo + runif(1, 0.5, 3); mb <- create.monomial.basis(c(lo, hi), nbs, ex); nd <- sample(0:3, 1)
  for (x in runif(3, lo, hi)) { v <- suppressWarnings(invisible(capture.output(vv <- eval.basis(x, mb, nd)))); for (j in 1:nbs) cases[[length(cases) + 1]] <- case("m", c(nbs, lo, hi, nd, x, j - 1, ex), vv[1, j], rel = 1e-9, abs = 1e-11) }
  nbs <- sample(2:5, 1); rt <- runif(nbs, -2, 2); eb <- create.exponential.basis(c(lo, hi), nbs, rt); nd <- sample(0:3, 1)
  for (x in runif(3, lo, hi)) { vv <- eval.basis(x, eb, nd); for (j in 1:nbs) cases[[length(cases) + 1]] <- case("x", c(nbs, lo, hi, nd, x, j - 1, rt), vv[1, j], rel = 1e-9, abs = 1e-11) }
  n <- sample(3:8, 1); av <- sort(runif(n, 0, 2)); pb <- create.polygonal.basis(av); nd <- sample(0:1, 1)
  for (x in c(runif(3, min(av), max(av)), min(av), max(av))) { vv <- eval.basis(x, pb, nd); for (j in 1:n) cases[[length(cases) + 1]] <- case("y", c(n, nd, x, j - 1, av), vv[1, j], rel = 1e-9, abs = 1e-11) }
  cb <- create.constant.basis(c(lo, hi)); nd <- sample(0:2, 1); x <- runif(1, lo, hi); cases[[length(cases) + 1]] <- case("k", c(nd, x), eval.basis(x, cb, nd)[1, 1], rel = 1e-9, abs = 1e-11)
}
for (rep in 1:10) {
  nbf <- 2 * sample(2:6, 1) + 1; per <- runif(1, 0.5, 5); fb <- create.fourier.basis(c(0, per), nbasis = nbf, period = per); m <- sample(1:3, 1); lam <- 10^sample(-6:0, 1)
  nd <- sample(20:60, 1); xs <- sort(runif(nd, 0, per)); ys <- sin(2 * pi * xs / per) + rnorm(nd, 0, 0.2)
  sm <- smooth.basis(xs, ys, fdPar(fb, m, lam)); cf <- as.vector(sm$fd$coefs)
  for (q in seq_along(cf)) cases[[length(cases) + 1]] <- case("s", c(nbf, per, m, lam, q - 1, nd, xs, ys), cf[q], rel = 1e-9, abs = 1e-11)
  cc <- rnorm(nbf); fdo <- fd(cc, fb); dd <- sample(0:2, 1)
  for (x in runif(4, 0, per)) cases[[length(cases) + 1]] <- case("w", c(nbf, per, dd, x, cc), as.numeric(eval.fd(x, fdo, dd)), rel = 1e-9, abs = 1e-10)
}
for (rep in 1:12) {
  nbr <- sample(3:6, 1); br <- sort(c(0, 1, runif(nbr - 2))); no <- sample(4:5, 1); basis <- create.bspline.basis(c(0, 1), norder = no, breaks = br); nbs <- basis$nbasis
  nrp <- sample(8:25, 1); cf <- matrix(rnorm(nbs * nrp), nbs, nrp) * (1 / seq_len(nbs)); m <- sample(1:2, 1); lam <- 10^sample(-5:0, 1)
  pc <- suppressWarnings(pca.fd(fd(cf, basis), nharm = 3, harmfdPar = fdPar(basis, m, lam)))
  for (k in 1:3) { cases[[length(cases) + 1]] <- case("Q", c(no, length(br), nrp, m, lam, k - 1, 0, br, cf), pc$values[k], rel = 1e-9, abs = 1e-11)
    cases[[length(cases) + 1]] <- case("Q", c(no, length(br), nrp, m, lam, k - 1, 1, br, cf), pc$varprop[k], rel = 1e-9, abs = 1e-11) }
}
for (rep in 1:5) {
  nbr <- sample(3:5, 1); br <- sort(c(0, 1, runif(nbr - 2))); no <- sample(4:5, 1); basis <- create.bspline.basis(c(0, 1), norder = no, breaks = br); nbs <- basis$nbasis
  N <- sample(25:40, 1); nf <- sample(1:2, 1); nz <- sample(0:2, 1); lams <- 10^sample(-4:0, nf, replace = TRUE)
  xc <- lapply(1:nf, function(f) matrix(rnorm(nbs * N), nbs, N)); zs <- lapply(seq_len(nz), function(k) rnorm(N)); y <- rnorm(N)
  xl <- c(list(const = rep(1, N)), setNames(zs, if (nz) paste0("z", 1:nz) else NULL), setNames(lapply(xc, function(m) fd(m, basis)), paste0("x", 1:nf)))
  bl <- c(list(fdPar(create.constant.basis(c(0, 1)))), lapply(seq_len(nz), function(k) fdPar(create.constant.basis(c(0, 1)))), lapply(1:nf, function(f) fdPar(basis, 2, lams[f])))
  names(bl) <- names(xl)
  fr <- fRegress(y, xl, bl)
  cf <- unlist(lapply(fr$betaestlist, function(b) as.vector(b$fd$coefs)))
  for (q in seq_along(cf)) cases[[length(cases) + 1]] <- case("M", c(no, length(br), N, nf, nz, q - 1, lams, br, unlist(xc), unlist(zs), y), cf[q], rel = 1e-9, abs = 1e-11)
}
emit("fda5", "fda", list(cases))
