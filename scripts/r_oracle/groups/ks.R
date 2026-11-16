# ks: hns, Hns and kde at points with a given H.
#   args: "hns" (n, r, x...); "Hns" (n, d, r, i, j, x...); "kde" (n, d, Hrowmajor d*d..., p d..., x...)
suppressMessages(library(ks))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-13)
set.seed(20262005)
for (rep in 1:25) {
  n <- sample(20:80, 1); d <- sample(1:3, 1); x <- matrix(round(rnorm(n * d, 0, 1.5), 4), n, d); r <- sample(0:2, 1)
  if (d == 1) add("hns", c(n, r, x), hns(as.vector(x), deriv.order = r))
  if (d >= 2) { Hm <- Hns(x, deriv.order = r); for (i in 1:d) for (j in 1:d) add("Hns", c(n, d, r, i - 1, j - 1, as.vector(t(x))), Hm[i, j]) }
  if (d >= 2) {
    A <- matrix(runif(d * d, -0.3, 0.3), d, d); H <- crossprod(A) + diag(runif(d, 0.1, 0.6)); H <- (H + t(H)) / 2
    for (rr in 1:3) { p <- rnorm(d); add("kde", c(n, d, as.vector(t(H)), p, as.vector(t(x))), kde(x, H = H, eval.points = matrix(p, 1, d), binned = FALSE)$estimate) }
  }
}
emit("ks", "ks", list(cases))
