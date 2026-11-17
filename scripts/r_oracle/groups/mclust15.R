# mclust, fifteenth part: hcRandomPairs under set.seed.
# "hrp" (n, seed, id): id -1 sum(position * entry) of the merge entries read column by column, 100 + g sum(i * hclass(h, g)[i])
suppressMessages(library(mclust))
cases <- list()
set.seed(20261223)
for (rep in 1:60) {
  n <- sample(5:60, 1); sd <- sample(1:100000, 1)
  X <- matrix(rnorm(n * 2), n, 2)
  h <- hcRandomPairs(X, seed = sd)
  v <- as.vector(unclass(h))
  add <- function(id, want) cases[[length(cases) + 1]] <<- case("hrp", c(n, sd, id), want, rel = 0, abs = 0)
  add(-1, sum(seq_along(v) * v))
  m <- ncol(h) + 1
  for (g in unique(c(n - m + 1, min(n, 3), min(n, 7)))) if (g >= n - ncol(h) && g <= n) { cl <- hclass(h, g)[, 1]; add(100 + g, sum(seq_len(n) * cl)) }
}
emit("mclust15", "mclust", list(cases))
