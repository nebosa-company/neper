# ks Hlscv and Hlscv.diag (unbinned) in three and four dimensions.
#   args: (n, d, diag, i, j, x row-major...)
suppressMessages(library(ks))
cases <- list()
add <- function(args, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case("Hlscv", args, want, rel = rel, abs = 1e-13)
set.seed(20262016)
for (d in 3:4) for (rep in 1:3) {
  n <- sample(40:70, 1)
  A <- matrix(runif(d * d, -1, 1), d, d)
  x <- round(matrix(rnorm(n * d), n, d) %*% A + matrix(rep(0:(d - 1), each = n) * 0.5, n, d), 5)
  xv <- as.vector(t(x))
  H <- suppressWarnings(Hlscv(x, binned = FALSE))
  for (i in 1:d) for (j in i:d) add(c(n, d, 0, i - 1, j - 1, xv), H[i, j])
  H <- suppressWarnings(Hlscv.diag(x, binned = FALSE))
  for (i in 1:d) add(c(n, d, 1, i - 1, i - 1, xv), H[i, i])
}
emit("kslscv", "ks", list(cases))
