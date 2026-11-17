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
# TSP default (arbitrary insertion + 2-opt): (8, n, D, order, seed, rep); rep > 1 restarts from sample.int seeds
for (rep in 1:100) {
  n <- sample(5:25, 1); x <- matrix(runif(n * 3), n, 3); d <- dist(x)
  rp <- c(1, 1, 3, 10)[(rep - 1) %% 4 + 1]; seed <- sample(1:100000, 1); set.seed(seed)
  o <- as.integer(get_order(seriate(d, "TSP", control = if (rp > 1) list(rep = rp) else NULL)))
  cases[[length(cases) + 1]] <- mk(8, n, d, o, c(seed, rp))
}
# ARSA (set.seed(seed)): (9, n, D, order, seed)
for (rep in 1:60) {
  n <- sample(3:20, 1); x <- matrix(runif(n * 3), n, 3); d <- dist(x)
  if (rep %% 4 == 0) d <- dist(round(x * 4))
  seed <- sample(1:100000, 1); set.seed(seed)
  o <- as.integer(get_order(suppressWarnings(seriate(d, "ARSA"))))
  cases[[length(cases) + 1]] <- mk(9, n, d, o, c(seed))
}
# GSA with each local search: (10, n, D, order, seed, kind 1 swap 2 insert 3 reverse 4 mixed)
lss <- c("LS_swap", "LS_insert", "LS_reverse", "LS_mixed")
for (rep in 1:40) {
  n <- sample(4:12, 1); x <- matrix(runif(n * 3), n, 3); d <- dist(x)
  kd <- (rep - 1) %% 4 + 1; seed <- sample(1:100000, 1); set.seed(seed)
  o <- as.integer(get_order(seriate(d, "GSA", control = list(localsearch = lss[kd]))))
  cases[[length(cases) + 1]] <- mk(10, n, d, o, c(seed, kd))
}
# Random, Identity, Reverse: (11, n, D, order, seed), 12, 13
for (rep in 1:12) {
  n <- sample(2:20, 1); x <- matrix(runif(n * 3), n, 3); d <- dist(x); seed <- sample(1:100000, 1); set.seed(seed)
  cases[[length(cases) + 1]] <- mk(11, n, d, as.integer(get_order(seriate(d, "Random"))), c(seed))
  cases[[length(cases) + 1]] <- mk(12, n, d, as.integer(get_order(seriate(d, "Identity"))), c(seed))
  cases[[length(cases) + 1]] <- mk(13, n, d, as.integer(get_order(seriate(d, "Reverse"))), c(seed))
}
# permute: "p" (n, D, order) a weighted sum of permute(d, order) as a matrix; "q" (nr, nc, X, row order, col order) of permute(X, ser_permutation(ro, co))
for (rep in 1:20) {
  n <- sample(3:15, 1); x <- matrix(runif(n * 3), n, 3); d <- dist(x); o <- sample(n)
  P <- as.matrix(permute(d, ser_permutation_vector(o))); w <- outer(1:n, 1:n, function(i, j) ((i * 7 + j * 3) %% 11) + 1)
  cases[[length(cases) + 1]] <- case("p", c(n, rowm(as.matrix(d)), o), sum(P * w), rel = 1e-12, abs = 1e-12)
  nr <- sample(2:9, 1); nc <- sample(2:9, 1); X <- matrix(runif(nr * nc), nr, nc); ro <- sample(nr); co <- sample(nc)
  Q <- permute(X, ser_permutation(ser_permutation_vector(ro), ser_permutation_vector(co))); w2 <- outer(1:nr, 1:nc, function(i, j) ((i * 5 + j * 3) %% 7) + 1)
  cases[[length(cases) + 1]] <- case("q", c(nr, nc, rowm(X), ro, co), sum(Q * w2), rel = 1e-12, abs = 1e-12)
  v <- runif(n); cases[[length(cases) + 1]] <- case("v", c(n, v, o), sum(permute(v, ser_permutation_vector(o)) * (1:n)), rel = 1e-12, abs = 1e-12)
}
emit("seriation_methods", "seriation", list(cases))
