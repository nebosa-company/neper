# ks Hpi.diag and Hscv.diag in two dimensions with the default samse pilot and pre = "scale", unbinned.
#   args: "Hpi.diag" / "Hscv.diag" (n, nstage, i, x row-major...), i the diagonal element (0 or 1)
suppressMessages(library(ks))
cases <- list()
add <- function(fn, args, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-13)
set.seed(20262018)
for (rep in 1:10) {
  n <- sample(40:160, 1)
  A <- matrix(runif(4, -1, 1), 2, 2)
  x <- round(cbind(rnorm(n), rnorm(n)) %*% A + cbind(rep(c(0, 2), length.out = n), rep(c(0, -1), length.out = n)), 5)
  xv <- as.vector(t(x))
  for (ns in 1:2) {
    H <- Hpi.diag(x, nstage = ns, binned = FALSE)
    for (i in 1:2) add("Hpi.diag", c(n, ns, i - 1, xv), H[i, i])
    H <- suppressWarnings(Hscv.diag(x, nstage = ns, binned = FALSE))
    for (i in 1:2) add("Hscv.diag", c(n, ns, i - 1, xv), H[i, i])
  }
}
emit("ks2ddiag", "ks", list(cases))
