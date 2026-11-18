# sampling::UPbrewer under set.seed. Args: (seed, N, pik[N], which): which 0 the sample size, 1 the sum of index * selected (1 based index).
suppressMessages(library(sampling))
cases <- list()
add <- function(fn, args, want, rel = 1e-12, abs = 1e-12) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261239)
for (rep in 1:20) {
  N <- sample(6:16, 1); n <- sample(2:(N - 2), 1)
  a <- runif(N, 0.5, 5)
  pik <- inclusionprobabilities(a, n)
  seed <- sample(1:1000000, 1)
  set.seed(seed)
  s <- UPbrewer(pik)
  add("br", c(seed, N, pik, 0), sum(s))
  add("br", c(seed, N, pik, 1), sum(seq_along(s) * s))
}
emit("sampling_brewer", "sampling", list(cases))
