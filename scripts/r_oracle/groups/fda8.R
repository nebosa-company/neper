# fda: eval.fd, deriv.fd and an unsmoothed pca.fd over the Fourier, monomial, exponential and polygonal bases.
#   kind 1 Fourier (range [0, period]), 2 monomial, 3 exponential, 4 polygonal; par = exponents / rates / argvals (zeros for Fourier)
#   e  eval.fd   (kind, nbasis, lo, hi, nd, x, par[nbasis], coefs[nbasis])
#   d  deriv.fd coefficient (kind, nbasis, lo, hi, nd, index, par[nbasis], coefs[nbasis])
#   p  pca.fd    (kind, nbasis, nrep, lo, hi, index, which 0 value 1 varprop, par[nbasis], coefs[nbasis nrep])
suppressMessages(library(fda))
cases <- list()
set.seed(20261207)
mk <- function(kind) {
  if (kind == 1) { nb <- 2 * sample(1:4, 1) + 1; per <- runif(1, 0.5, 4); list(kind = kind, nb = nb, lo = 0, hi = per, par = rep(0, nb), basis = create.fourier.basis(c(0, per), nbasis = nb, period = per)) }
  else if (kind == 2) { nb <- sample(2:4, 1); ex <- sort(sample(0:5, nb)); lo <- runif(1, 0, 0.5); hi <- lo + runif(1, 0.5, 2); list(kind = kind, nb = nb, lo = lo, hi = hi, par = ex, basis = create.monomial.basis(c(lo, hi), nb, ex)) }
  else if (kind == 3) { nb <- sample(2:5, 1); rt <- runif(nb, -2, 2); lo <- runif(1, 0, 0.5); hi <- lo + runif(1, 0.5, 2); list(kind = kind, nb = nb, lo = lo, hi = hi, par = rt, basis = create.exponential.basis(c(lo, hi), nb, rt)) }
  else { nb <- sample(3:8, 1); av <- sort(runif(nb, 0, 2)); list(kind = kind, nb = nb, lo = min(av), hi = max(av), par = av, basis = create.polygonal.basis(av)) }
}
for (kind in 1:4) for (rep in 1:8) {
  s <- mk(kind); nb <- s$nb
  if (kappa(crossprod(eval.basis(seq(s$lo, s$hi, len = 10 * nb + 1), s$basis)), exact = TRUE) > 1e6) next
  cf <- rnorm(nb); f <- fd(cf, s$basis)
  nd <- sample(0:2, 1)
  for (x in runif(3, s$lo, s$hi)) cases[[length(cases) + 1]] <- case("e", c(kind, nb, s$lo, s$hi, nd, x, s$par, cf), as.numeric(eval.fd(x, f, nd)), rel = 1e-9, abs = 1e-10)
  for (m in 1:2) { dc <- as.vector(deriv.fd(f, m)$coefs)
    for (q in seq_along(dc)) cases[[length(cases) + 1]] <- case("d", c(kind, nb, s$lo, s$hi, m, q - 1, s$par, cf), dc[q], rel = 1e-9, abs = 1e-9) }
  if (kind >= 2) {
    nrp <- sample(8:20, 1); cm <- matrix(rnorm(nb * nrp), nb, nrp) * (1 / seq_len(nb))
    pc <- suppressWarnings(pca.fd(fd(cm, s$basis), nharm = min(3, nb)))
    for (k in 1:min(3, nb)) for (w in 0:1) cases[[length(cases) + 1]] <- case("p", c(kind, nb, nrp, s$lo, s$hi, k - 1, w, s$par, cm), if (w == 0) pc$values[k] else pc$varprop[k], rel = 1e-9, abs = 1e-11)
  }
}
emit("fda8", "fda", list(cases))
