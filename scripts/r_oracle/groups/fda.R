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
emit("fda", "fda", list(cases))
