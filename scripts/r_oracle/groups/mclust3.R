# mclust, third part: hc for VII and VVV with every use transform, and hclass.
# "hc3" (model 0 VII 1 VVV, use 0 VARS 1 STD 2 PCR 3 PCS 4 SPH 5 SVD, n, p, id, X[n p] column-major): id -1 sum(position * entry) over the 2 (n - 1) merge entries read column by column, id 0 1 2 the first three merges as 1000 a + b
# "hcl" (model, use, n, p, g, X): sum(i * hclass(hc, g)[i])
# "hc1" (model 0 E 1 V, n, id, x[n]): hc of one variable, see the end of the file
suppressMessages(library(mclust))
cases <- list()
set.seed(20261201)
uses <- c("VARS", "STD", "PCR", "PCS", "SPH", "SVD")
for (rep in 1:90) {
  mo <- rep %% 2; us <- sample(0:5, 1); n <- sample(8:45, 1); p <- sample(2:4, 1)
  cl <- sample(3, n, TRUE); X <- matrix(rnorm(n * p), n, p) * rep(runif(p, 0.5, 2), each = n) + 2 * (cl - 1)
  h <- suppressWarnings(hc(X, modelName = c("VII", "VVV")[mo + 1], use = uses[us + 1]))
  v <- as.vector(unclass(h)[1:2, ])
  add <- function(id, want) cases[[length(cases) + 1]] <<- case("hc3", c(mo, us, n, p, id, X), want, rel = 0, abs = 0)
  add(-1, sum(seq_along(v) * v)); for (s in 1:3) add(s - 1, 1000 * v[2 * s - 1] + v[2 * s])
  for (g in sample(2:min(6, n - 1), 2)) { cl2 <- hclass(h, g)[, 1]; cases[[length(cases) + 1]] <- case("hcl", c(mo, us, n, p, g, X), sum(seq_len(n) * cl2), rel = 0, abs = 0) }
}
# "hc1" (model 0 E 1 V, n, id, x[n]): one variable, id -1 sum(position * entry) of the merge pairs, id 0 the first merge as 1000 a + b
for (rep in 1:40) {
  mo <- rep %% 2; n <- sample(6:50, 1); x <- rnorm(n) * runif(1, 0.5, 3) + 2 * sample(0:2, n, TRUE)
  h <- suppressWarnings(hc(x, modelName = c("E", "V")[mo + 1])); v <- as.vector(unclass(h)[1:2, ])
  cases[[length(cases) + 1]] <- case("hc1", c(mo, n, -1, x), sum(seq_along(v) * v), rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("hc1", c(mo, n, 0, x), 1000 * v[1] + v[2], rel = 0, abs = 0)
}
emit("mclust3", "mclust", list(cases))
