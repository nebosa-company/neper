# fda: fRegress with a functional response (B-spline curves; constant covariates with the constant basis, functional covariates with B-spline betas).
#   F  coefficient of beta (index): (index, N, noy, nbry, p, [type, nox, nbrx, nob, nbrb, lambda] x p, ybreaks[nbry], ycoefs[nby N], then per covariate xbreaks[nbrx], bbreaks[nbrb], xcoefs[nbx N])
#   type 0 constant covariate (basis constant, one coefficient per curve), 1 functional covariate
suppressMessages(library(fda))
cases <- list()
set.seed(20261208)
rb <- function() { n <- sample(3:5, 1); sort(c(0, 1, runif(n - 2))) }
for (rep in 1:7) {
  N <- sample(12:20, 1); noy <- 4; bry <- rb(); yb <- create.bspline.basis(c(0, 1), norder = noy, breaks = bry); nby <- yb$nbasis
  yc <- matrix(rnorm(nby * N), nby, N); yfd <- fd(yc, yb)
  nf <- sample(1:2, 1); nz <- sample(0:1, 1)
  xl <- list(const = rep(1, N)); bl <- list(const = fdPar(create.constant.basis(c(0, 1)))); heads <- c(0, 0, 0, 0, 0, 0); body <- list()
  if (nz) { z <- rnorm(N); xl$z <- z; bl$z <- fdPar(create.constant.basis(c(0, 1))); heads <- c(heads, 0, 0, 0, 0, 0, 0); body <- c(body, list(z)) }
  body <- c(list(rep(1, N)), body)
  for (f in 1:nf) {
    nox <- sample(4:5, 1); brx <- rb(); xb <- create.bspline.basis(c(0, 1), norder = nox, breaks = brx); xcf <- matrix(rnorm(xb$nbasis * N), xb$nbasis, N) / seq_len(xb$nbasis)
    nob <- 4; brb <- rb(); bb <- create.bspline.basis(c(0, 1), norder = nob, breaks = brb); lam <- 10^sample(-4:-1, 1)
    xl[[paste0("x", f)]] <- fd(xcf, xb); bl[[paste0("x", f)]] <- fdPar(bb, 2, lam)
    heads <- c(heads, 1, nox, length(brx), nob, length(brb), lam); body <- c(body, list(c(brx, brb, xcf)))
  }
  fr <- fRegress(yfd, xl, bl)
  cf <- unlist(lapply(fr$betaestlist, function(b) as.vector(b$fd$coefs)))
  p <- length(xl)
  hv <- matrix(heads, nrow = 6)
  for (q in seq_along(cf)) cases[[length(cases) + 1]] <- case("F", c(q - 1, N, noy, length(bry), p, heads, bry, yc, unlist(body)), cf[q], rel = 1e-9, abs = 1e-10)
}
emit("fda9", "fda", list(cases))
