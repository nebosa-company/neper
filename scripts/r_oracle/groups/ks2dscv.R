# ks, two dimensions: Hscv (samse pilot, sphering, unbinned SCV).
#   args: "Hscv" (n, nstage, i, j, x row-major...)
suppressMessages(library(ks))
cases <- list()
add <- function(fn, args, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-13)
set.seed(20262008)
for (rep in 1:10) {
  n <- sample(40:140, 1)
  A <- matrix(runif(4, -1, 1), 2, 2)
  x <- round(cbind(rnorm(n), rnorm(n)) %*% A + cbind(rep(c(0, 2), length.out = n), rep(c(0, -1), length.out = n)), 5)
  xv <- as.vector(t(x))
  for (ns in 1:2) {
    H <- Hpi(x, nstage = ns, binned = TRUE)
    for (i in 1:2) for (j in i:2) add("Hpib", c(n, ns, i - 1, j - 1, xv), H[i, j], rel = 1e-11)
    H <- Hscv(x, nstage = ns, binned = FALSE)
    for (i in 1:2) for (j in i:2) add("Hscv", c(n, ns, i - 1, j - 1, xv), H[i, j], rel = 1e-6)
  }
}
emit("ks2dscv", "ks", list(cases))
