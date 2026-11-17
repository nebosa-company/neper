# fda: the B-spline basis of create.bspline.basis evaluated by eval.basis.
#   args: (norder, number of breaks incl. the end points, deriv, x, j (0-based basis function), breaks...)
suppressMessages(library(fda))
cases <- list()
set.seed(20261202)
for (rep in 1:25) {
  nbr <- sample(3:9, 1); br <- sort(c(0, 1, runif(nbr - 2))) * runif(1, 0.5, 4); no <- sample(2:6, 1); basis <- create.bspline.basis(range(br), norder = no, breaks = br)
  nd <- min(sample(0:2, 1), no - 1); xs <- c(runif(4, min(br), max(br)), br[2])
  for (x in xs) { v <- eval.basis(x, basis, Lfdobj = nd)
    for (j in seq_len(ncol(v))) cases[[length(cases) + 1]] <- case("b", c(no, length(br), nd, x, j - 1, br), v[1, j], rel = 1e-9, abs = 1e-11) }
}
# the roughness penalty "pen" (norder, nb, m, index, breaks) and smooth.basis coefficients "sm" (norder, nb, m, lambda, index, nd, breaks, argvals, y)
for (rep in 1:20) {
  nbr <- sample(3:8, 1); br <- sort(c(0, 1, runif(nbr - 2))); no <- sample(4:6, 1); basis <- create.bspline.basis(c(0, 1), norder = no, breaks = br); m <- sample(1:2, 1)
  P <- getbasispenalty(basis, Lfdobj = m); for (q in c(1, 5, 12, length(P))) cases[[length(cases) + 1]] <- case("pen", c(no, length(br), m, q - 1, br), as.vector(P)[q], rel = 1e-8, abs = 1e-11)
  nd <- sample(25:60, 1); xs <- sort(runif(nd)); ys <- sin(2 * pi * xs) + rnorm(nd, 0, 0.2); lam <- 10^sample(-6:-1, 1)
  fdp <- fdPar(basis, Lfdobj = m, lambda = lam); sm <- smooth.basis(xs, ys, fdp); cf <- as.vector(sm$fd$coefs)
  for (q in seq_along(cf)) cases[[length(cases) + 1]] <- case("sm", c(no, length(br), m, lam, q - 1, nd, br, xs, ys), cf[q], rel = 1e-6, abs = 1e-9)
}
# Fourier basis "f": (nbasis, period, deriv, x, j)
for (rep in 1:20) {
  nbf <- 2 * sample(1:5, 1) + 1; per <- runif(1, 0.5, 5); fb <- create.fourier.basis(c(0, per), nbasis = nbf, period = per); nd <- sample(0:3, 1)
  for (x in runif(4, 0, per)) { v <- eval.basis(x, fb, Lfdobj = nd); for (j in seq_len(nbf)) cases[[length(cases) + 1]] <- case("f", c(nbf, per, nd, x, j - 1), v[1, j], rel = 1e-9, abs = 1e-10) }
}
# smooth.basis df, sse, gcv and coefficients with and without weights "g"
for (rep in 1:20) {
  nbr <- sample(3:7, 1); br <- sort(c(0, 1, runif(nbr - 2))); no <- sample(4:5, 1); basis <- create.bspline.basis(c(0, 1), norder = no, breaks = br); m <- 2
  nd <- sample(25:60, 1); xs <- sort(runif(nd)); ys <- sin(2 * pi * xs) + rnorm(nd, 0, 0.2); lam <- 10^sample(-5:-1, 1); hw <- rep %% 2; ww <- if (hw) runif(nd, 0.3, 2) else rep(1, nd)
  fdp <- fdPar(basis, Lfdobj = m, lambda = lam); sm <- smooth.basis(xs, ys, fdp, wtvec = ww); cf <- as.vector(sm$fd$coefs)
  args <- function(w) c(no, length(br), m, lam, w, hw, nd, br, xs, ys, if (hw) ww else numeric(0))
  cases[[length(cases) + 1]] <- case("g", args(0), sm$df, rel = 1e-7, abs = 1e-9); cases[[length(cases) + 1]] <- case("g", args(1), sm$SSE, rel = 1e-6, abs = 1e-9)
  cases[[length(cases) + 1]] <- case("g", args(2), sm$gcv, rel = 1e-6, abs = 1e-9)
  for (q in seq_along(cf)) cases[[length(cases) + 1]] <- case("g", args(3 + q - 1), cf[q], rel = 1e-6, abs = 1e-9)
}
emit("fda", "fda", list(cases))
