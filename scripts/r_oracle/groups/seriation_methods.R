# seriation (1.6.0), the seriation methods of dist: "m" args (code, n, D[n*n] row-major, R's order[n] 1-based, extra...), value 1.
#   code 1 Spectral  2 Spectral_norm  3 MDS  4 MDS_angle  (compared up to reversal: LAPACK fixes the eigenvector sign)
#   code 5 BEA row order, 6 BEA col order of a matrix (args: 5, nr, nc, X[nr*nc] row-major, seed, row order[nr], col order[nc])
#   code 7 TSP(insertion method, no 2-opt, rep 1): args 7, n, D, order, seed, method (1 nearest 2 farthest 3 cheapest 4 arbitrary)
#   code 8 TSP default (arbitrary insertion + 2-opt, rep 10), args 8, n, D, order, seed
#   code 9 ARSA: args 9, n, D, order, seed
#   code 10 GSA/SA default: args 10, n, D, order, seed
#   code 11 Random: args 11, n, D, order, seed; 12 Identity; 13 Reverse
suppressMessages(library(seriation))
cases <- list()
set.seed(20261117)
rowm <- function(M) as.vector(t(M))
mk <- function(code, n, d, o, extra = numeric(0)) case("m", c(code, n, rowm(as.matrix(d)), o, extra), 1, rel = 0, abs = 0)
for (rep in 1:80) {
  n <- sample(5:25, 1); x <- matrix(runif(n * 3), n, 3); d <- dist(x)
  for (mm in list(c("Spectral", 1), c("Spectral_norm", 2), c("MDS", 3), c("MDS_angle", 4))) {
    o <- as.integer(get_order(suppressWarnings(seriate(d, method = mm[1]))))
    cases[[length(cases) + 1]] <- mk(as.numeric(mm[2]), n, d, o)
  }
}
emit("seriation_methods", "seriation", list(cases))
