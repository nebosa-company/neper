# fda: smooth.fd and pca.fd on a Fourier basis.
#   D  smooth.fd (nbasis, period, m, lambda, nrep, index, coefs[nbasis nrep])
#   F  pca.fd with harmfdPar = fdPar(fourier basis, m, lambda) (nbasis, period, nrep, m, lambda, index, which 0 value 1 varprop, coefs[nbasis nrep])
suppressMessages(library(fda))
cases <- list()
set.seed(20261207)
for (rep in 1:10) {
  nbf <- 2 * sample(2:6, 1) + 1; per <- runif(1, 0.5, 5); fb <- create.fourier.basis(c(0, per), nbasis = nbf, period = per); m <- sample(1:3, 1); lam <- 10^sample(-6:0, 1)
  nrp <- sample(2:5, 1); cf <- matrix(rnorm(nbf * nrp), nbf, nrp); sm <- smooth.fd(fd(cf, fb), fdPar(fb, m, lam)); v <- as.vector(sm$coefs)
  for (q in seq_along(v)) cases[[length(cases) + 1]] <- case("D", c(nbf, per, m, lam, nrp, q - 1, cf), v[q], rel = 1e-9, abs = 1e-11)
}
for (rep in 1:10) {
  nbf <- 2 * sample(2:6, 1) + 1; per <- runif(1, 0.5, 5); fb <- create.fourier.basis(c(0, per), nbasis = nbf, period = per); m <- sample(1:3, 1); lam <- c(0, 10^(-6:0))[sample(1:8, 1)]
  nrp <- sample(8:25, 1); cf <- matrix(rnorm(nbf * nrp), nbf, nrp) * (1 / seq_len(nbf))
  pc <- suppressWarnings(pca.fd(fd(cf, fb), nharm = 3, harmfdPar = fdPar(fb, m, lam)))
  for (k in 1:3) { cases[[length(cases) + 1]] <- case("F", c(nbf, per, nrp, m, lam, k - 1, 0, cf), pc$values[k], rel = 1e-9, abs = 1e-11)
    cases[[length(cases) + 1]] <- case("F", c(nbf, per, nrp, m, lam, k - 1, 1, cf), pc$varprop[k], rel = 1e-9, abs = 1e-11) }
}
emit("fda7", "fda", list(cases))
