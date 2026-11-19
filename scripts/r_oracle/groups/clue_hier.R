# clue: cl_dissimilarity of two hclust trees. Args: (kind 0 euclidean 1 manhattan 2 cophenetic 3 gamma 4 Chebyshev, n, method1, method2 (1 ward.D 2 single 3 complete 4 average 5 mcquitty 8 ward.D2), x1 row-major n x 2, x2 row-major n x 2)
suppressMessages(library(clue))
cases <- list()
set.seed(20262410)
meth <- c("ward.D", "single", "complete", "average", "mcquitty", "median", "centroid", "ward.D2")
for (rep in 1:40) {
  n <- sample(6:30, 1); x1 <- matrix(round(rnorm(n * 2) * 3, 3), n, 2); x2 <- x1 + matrix(round(rnorm(n * 2, 0, 0.8), 3), n, 2)
  m1 <- sample(c(1, 2, 3, 4, 5, 8), 1); m2 <- sample(c(1, 2, 3, 4, 5, 8), 1)
  h1 <- hclust(dist(x1), meth[m1]); h2 <- hclust(dist(x2), meth[m2])
  for (kd in 0:4) {
    nm <- c("euclidean", "manhattan", "cophenetic", "gamma", "Chebyshev")[kd + 1]
    r <- tryCatch(as.numeric(cl_dissimilarity(h1, h2, method = nm)), error = function(e) NULL)
    if (is.null(r)) next
    cases[[length(cases) + 1]] <- case("hier", c(kd, n, m1, m2, as.vector(t(x1)), as.vector(t(x2))), r, rel = 1e-9, abs = 1e-10)
  }
}
# kinds 5 .. 10: cl_agreement cophenetic, angle, gamma, euclidean, manhattan, and the symdiff dissimilarity
for (rep in 1:40) {
  n <- sample(6:30, 1); x1 <- matrix(round(rnorm(n * 2) * 3, 3), n, 2); x2 <- x1 + matrix(round(rnorm(n * 2, 0, 0.8), 3), n, 2)
  m1 <- sample(c(1, 2, 3, 4, 5, 8), 1); m2 <- sample(c(1, 2, 3, 4, 5, 8), 1)
  h1 <- hclust(dist(x1), meth[m1]); h2 <- hclust(dist(x2), meth[m2])
  for (kd in 5:10) {
    r <- tryCatch(as.numeric(if (kd == 10) cl_dissimilarity(h1, h2, "symdiff") else cl_agreement(h1, h2, method = c("cophenetic", "angle", "gamma", "euclidean", "manhattan")[kd - 4])), error = function(e) NULL)
    if (is.null(r)) next
    cases[[length(cases) + 1]] <- case("hier", c(kd, n, m1, m2, as.vector(t(x1)), as.vector(t(x2))), r, rel = 1e-9, abs = 1e-10)
  }
}
# "soft" (n, k, U row-major n x k, V row-major n x k): the Euclidean dissimilarity of two soft partitions
for (rep in 1:40) {
  n <- sample(8:40, 1); k <- sample(2:5, 1)
  U <- matrix(rexp(n * k), n, k); U <- U / rowSums(U); V <- matrix(rexp(n * k), n, k); V <- V / rowSums(V)
  r <- tryCatch(as.numeric(cl_dissimilarity(as.cl_partition(U), as.cl_partition(V), method = "euclidean")), error = function(e) NULL)
  if (is.null(r)) next
  cases[[length(cases) + 1]] <- case("soft", c(n, k, as.vector(t(U)), as.vector(t(V))), r, rel = 1e-9, abs = 1e-10)
}
emit("clue_hier", "clue", list(cases))
