# fda, the pieces built on the B-spline basis: deriv.fd, smooth.fd, monfn, mongrad, eval.monfd, zerobasis, smooth.morph, landmarkreg.
#   d   deriv.fd coefficient   (norder, nb, m, index, breaks, coefs)
#   s   smooth.fd coefficient   (norder, nb, m, lambda, nrep, index, breaks, coefs[nbasis nrep])
#   f   monfn                   (norder, nb, x, breaks, coefs)
#   g   mongrad column k        (norder, nb, x, k, breaks, coefs)
#   e   eval.monfd              (norder, nb, x, deriv, breaks, coefs)
#   z   zerobasis(k)[row, col]  (k, row, col)
suppressMessages(library(fda))
cases <- list()
set.seed(20261203)
rb <- function() { nbr <- sample(3:7, 1); sort(c(0, 1, runif(nbr - 2))) }
# deriv.fd
for (rep in 1:12) {
  br <- rb(); no <- sample(4:6, 1); basis <- create.bspline.basis(c(0, 1), norder = no, breaks = br); cf <- rnorm(basis$nbasis); m <- sample(1:min(3, no - 1), 1)
  d <- deriv.fd(fd(cf, basis), m); dc <- as.vector(d$coefs)
  for (q in seq_along(dc)) cases[[length(cases) + 1]] <- case("d", c(no, length(br), m, q - 1, br, cf), dc[q], rel = 1e-9, abs = 1e-10)
}
# smooth.fd
for (rep in 1:12) {
  br <- rb(); no <- sample(4:6, 1); basis <- create.bspline.basis(c(0, 1), norder = no, breaks = br); nbs <- basis$nbasis
  nrp <- sample(1:4, 1); cf <- matrix(rnorm(nbs * nrp), nbs, nrp); m <- sample(1:min(3, no - 1), 1); lam <- 10^sample(-6:-1, 1)
  # an ill-conditioned normal matrix makes R's and any other LU differ by cond * 1e-16: keep the draws that can be compared at 1e-9
  if (kappa(inprod(basis, basis) + lam * getbasispenalty(basis, m), exact = TRUE) > 1e6) next
  s <- smooth.fd(fd(cf, basis), fdPar(basis, m, lam)); sc <- as.vector(s$coefs)
  for (q in seq_along(sc)) cases[[length(cases) + 1]] <- case("s", c(no, length(br), m, lam, nrp, q - 1, br, cf), sc[q], rel = 1e-9, abs = 1e-10)
}
# monfn, mongrad, eval.monfd
for (rep in 1:10) {
  br <- rb(); no <- sample(4:5, 1); lo <- 0; basis <- create.bspline.basis(c(0, 1), norder = no, breaks = br); cf <- rnorm(basis$nbasis, 0, 0.7); W <- fd(cf, basis)
  for (x in c(runif(3), 0, 1)) {
    cases[[length(cases) + 1]] <- case("f", c(no, length(br), x, br, cf), monfn(x, W), rel = 1e-9, abs = 1e-11)
    gr <- mongrad(x, W); for (k in c(1, basis$nbasis)) cases[[length(cases) + 1]] <- case("g", c(no, length(br), x, k - 1, br, cf), gr[1, k], rel = 1e-9, abs = 1e-11)
    for (dv in 0:3) cases[[length(cases) + 1]] <- case("e", c(no, length(br), x, dv, br, cf), as.numeric(eval.monfd(x, W, dv)), rel = 1e-9, abs = 1e-11)
  }
}
# a basis with no interior knots "b": (norder, deriv, x, j, lo, hi)
for (no in 2:6) for (rng in list(c(0, 1), c(0.3, 2.1))) {
  basis <- create.bspline.basis(rng, norder = no, breaks = rng)
  for (x in c(rng[1], runif(3, rng[1], rng[2]), rng[2])) for (nd in 0:min(2, no - 1)) { v <- eval.basis(x, basis, Lfdobj = nd); for (j in seq_len(ncol(v))) cases[[length(cases) + 1]] <- case("b", c(no, nd, x, j - 1, rng), v[1, j], rel = 1e-9, abs = 1e-11) }
}
# getbasispenalty with no interior knots answers the monomial penalty "n": (norder, m, index, lo, hi)
for (no in 3:6) for (rng in list(c(0, 1), c(0.3, 2.1))) for (m in 0:2) {
  basis <- create.bspline.basis(rng, norder = no, breaks = rng); P <- getbasispenalty(basis, m)
  for (q in seq_along(P)) cases[[length(cases) + 1]] <- case("n", c(no, m, q - 1, rng), P[q], rel = 1e-10, abs = 1e-12)
}
# zerobasis
for (k in c(2, 3, 4, 5, 6, 8)) { zb <- zerobasis(k); for (r in seq_len(nrow(zb))) for (cc in seq_len(ncol(zb))) cases[[length(cases) + 1]] <- case("z", c(k, r - 1, cc - 1), zb[r, cc], rel = 1e-11, abs = 1e-13) }
emit("fda2", "fda", list(cases))
