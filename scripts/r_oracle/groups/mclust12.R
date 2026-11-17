# mclust, twelfth part: hc for EEE (hceee) from the singleton and from the duplicate-row initial partition (dupPartition).
# "hce" (n, p, mode, id, X[n p] column-major): mode 0 the singleton partition (the default of hc), 1 partition = dupPartition(X); id -1 sum(position * entry) over the merge entries read column by column, id 0 1 2 the first three merges as 1000 a + b,
# id 100 + g the sum(i * hclass(hc, g)[i]) for g clusters
suppressMessages(library(mclust))
cases <- list()
set.seed(20261219)
for (rep in 1:60) {
  n <- sample(6:45, 1); p <- sample(2:5, 1)
  cl <- sample(3, n, TRUE)
  X <- matrix(rnorm(n * p), n, p) * rep(runif(p, 0.5, 2), each = n) + c(0, 2, 5)[cl] * (rep < 40)
  if (rep > 40) { k <- sample(n, max(2, n %/% 4)); X[k, ] <- X[sample(setdiff(seq_len(n), k), length(k), TRUE), ] }
  mode <- as.numeric(rep > 40)
  h <- tryCatch(suppressWarnings(if (mode) hc(X, modelName = "EEE", partition = dupPartition(X)) else hc(X, modelName = "EEE")), error = function(e) NULL)
  if (is.null(h)) next
  m <- unclass(h); v <- as.vector(m[1:2, ])
  add <- function(id, want) cases[[length(cases) + 1]] <<- case("hce", c(n, p, mode, id, X), want, rel = 0, abs = 0)
  add(-1, sum(seq_along(v) * v)); for (s in 1:min(3, ncol(m))) add(s - 1, 1000 * v[2 * s - 1] + v[2 * s])
  k <- length(unique(attr(h, "initialPartition")))
  if (k >= 3) for (g in unique(sample(2:(k - 1), min(2, k - 2), replace = k - 2 < 2))) { c2 <- hclass(h, g)[, 1]; add(100 + g, sum(seq_len(n) * c2)) }
}
emit("mclust12", "mclust", list(cases))
