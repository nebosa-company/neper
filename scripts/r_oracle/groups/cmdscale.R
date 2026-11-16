# base R cmdscale (classical MDS) of Euclidean and non-Euclidean distance matrices; coordinates compared as absolute values.
#   args: (n, k, D[n*n] row-major)
#   fn "eig" (the k leading eigenvalues weighted by position), "coords" (absolute coordinates weighted by position, row-major)
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-7, abs = 1e-9)
set.seed(20270111)
for (rep in 1:24) {
  n <- sample(5:25, 1); p <- sample(2:5, 1); k <- sample(1:min(3, n - 2), 1); x <- matrix(rnorm(n * p), n)
  D <- as.matrix(dist(x, if (rep %% 3 == 0) "manhattan" else "euclidean"))
  r <- cmdscale(D, k = k, eig = TRUE); if (any(r$eig[seq_len(k)] <= 1e-8)) next
  a <- c(n, k, as.vector(t(D)))
  add("eig", a, sum(r$eig[seq_len(k)] * seq_len(k))); add("coords", a, sum(abs(as.vector(t(r$points))) * seq_len(n * k)))
}
emit("cmdscale", character(0), list(cases))
