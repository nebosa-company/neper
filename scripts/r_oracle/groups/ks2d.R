# ks, two dimensions: Hpi (samse pilot, sphering, unbinned), Hlscv, Hlscv.diag (unbinned).
#   args: "Hpi" (n, nstage, i, j, x row-major...); "Hlscv" (n, diag, i, j, x row-major...)
suppressMessages(library(ks))
cases <- list()
add <- function(fn, args, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-13)
set.seed(20262007)
for (rep in 1:12) {
  n <- sample(40:160, 1)
  A <- matrix(runif(4, -1, 1), 2, 2)
  x <- round(cbind(rnorm(n), rnorm(n)) %*% A + cbind(rep(c(0, 2), length.out = n), rep(c(0, -1), length.out = n)), 5)
  xv <- as.vector(t(x))
  for (ns in 1:2) {
    H <- Hpi(x, nstage = ns, binned = FALSE)
    for (i in 1:2) for (j in i:2) add("Hpi", c(n, ns, i - 1, j - 1, xv), H[i, j])
  }
  if (rep <= 8) {
    H <- suppressWarnings(Hlscv(x, binned = FALSE))
    for (i in 1:2) for (j in i:2) add("Hlscv", c(n, 0, i - 1, j - 1, xv), H[i, j], rel = 1e-9)
    H <- suppressWarnings(Hlscv.diag(x, binned = FALSE))
    for (i in 1:2) add("Hlscv", c(n, 1, i - 1, i - 1, xv), H[i, i], rel = 1e-9)
  }
}
#   "HpiB" (n, nstage, i, j, x row-major...): Hpi(x, nstage, binned = TRUE), the form ks uses above 500 observations
for (rep in 1:6) {
  n <- sample(60:200, 1)
  A <- matrix(runif(4, -1, 1), 2, 2)
  x <- round(cbind(rnorm(n), rnorm(n)) %*% A + cbind(rep(c(0, 2), length.out = n), rep(c(0, -1), length.out = n)), 5)
  xv <- as.vector(t(x))
  for (ns in 1:2) {
    H <- Hpi(x, nstage = ns, binned = TRUE)
    for (i in 1:2) for (j in i:2) add("HpiB", c(n, ns, i - 1, j - 1, xv), H[i, j])
  }
}
emit("ks2d", "ks", list(cases))
