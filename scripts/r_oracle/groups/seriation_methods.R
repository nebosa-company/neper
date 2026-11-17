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

# BEA: set.seed(seed); seriate(X, "BEA"); "m" codes 5 (row order) and 6 (column order): (code, nr, nc, X row-major, order, seed)
for (rep in 1:40) {
  nr <- sample(3:12, 1); nc <- sample(3:12, 1); X <- matrix(round(runif(nr * nc) * 5), nr, nc)
  seed <- sample(1:100000, 1); set.seed(seed)
  s <- seriate(X, "BEA")
  cases[[length(cases) + 1]] <- case("m", c(5, nr, nc, rowm(X), get_order(s, 1), seed), 1, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("m", c(6, nr, nc, rowm(X), get_order(s, 2), seed), 1, rel = 0, abs = 0)
}
# TSP insertion heuristics without 2-opt: (7, n, D, order, seed, method 1 nearest 2 farthest 3 cheapest 4 arbitrary)
meths <- c("nearest_insertion", "farthest_insertion", "cheapest_insertion", "arbitrary_insertion")
for (rep in 1:80) {
  n <- sample(5:25, 1); x <- matrix(runif(n * 3), n, 3); d <- dist(x)
  if (rep %% 3 == 0) d <- dist(round(x * 4))
  mi <- (rep - 1) %% 4 + 1; seed <- sample(1:100000, 1); set.seed(seed)
  o <- as.integer(get_order(seriate(d, "TSP", control = list(method = meths[mi]))))
  cases[[length(cases) + 1]] <- mk(7, n, d, o, c(seed, mi))
}
# TSP default (arbitrary insertion + 2-opt, rep 1), informational (2-opt is compiled C): fn "t" (8, n, D, order, seed)
for (rep in 1:80) {
  n <- sample(5:25, 1); x <- matrix(runif(n * 3), n, 3); d <- dist(x)
  seed <- sample(1:100000, 1); set.seed(seed)
  o <- as.integer(get_order(seriate(d, "TSP")))
  cases[[length(cases) + 1]] <- case("t", c(8, n, rowm(as.matrix(d)), o, seed), 1, rel = 0, abs = 0)
}
emit("seriation_methods", "seriation", list(cases))
