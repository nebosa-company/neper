# spdep moran.test and geary.test on a dense weights matrix from a random neighbour graph (binary or row-standardised).
#   args: (n, x[n], W[n*n] row-major)
#   fn "I" "EI" "varN" "varR" (Moran), "C" "varNg" "varRg" (Geary)
suppressMessages(library(spdep))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-11)
set.seed(20261217)
for (rep in 1:24) {
  n <- sample(12:60, 1); co <- matrix(runif(2 * n), n); k <- sample(2:5, 1)
  nb <- knn2nb(knearneigh(co, k = k)); if (rep %% 3 == 0) nb <- make.sym.nb(nb)
  sty <- c("W", "B", "C")[rep %% 3 + 1]
  lw <- nb2listw(nb, style = sty); W <- listw2mat(lw)
  x <- rnorm(n) + co[, 1] * 2
  m <- moran.test(x, lw, randomisation = TRUE); mn <- moran.test(x, lw, randomisation = FALSE)
  g <- geary.test(x, lw, randomisation = TRUE); gn <- geary.test(x, lw, randomisation = FALSE)
  a <- c(n, x, as.vector(t(W)))
  add("I", a, m$estimate[[1]]); add("EI", a, m$estimate[[2]]); add("varN", a, mn$estimate[[3]]); add("varR", a, m$estimate[[3]])
  add("C", a, g$estimate[[1]]); add("varNg", a, gn$estimate[[3]]); add("varRg", a, g$estimate[[3]])
}
emit("spdep", "spdep", list(cases))
