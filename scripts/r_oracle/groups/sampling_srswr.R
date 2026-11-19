# sampling: srswr(n, N) under set.seed (R's rbinom inversion sampler, so n * min(p, 1 - p) < 30). Args: (N, n, seed): the position-weighted sum of the counts.
suppressMessages(library(sampling))
cases <- list()
set.seed(20262330)
for (rep in 1:40) {
  N <- sample(5:60, 1); n <- sample(2:min(40, N), 1); sd <- sample(1:100000, 1)
  set.seed(sd); s <- srswr(n, N)
  cases[[length(cases) + 1]] <- case("sw", c(N, n, sd), sum(s * seq_len(N)), rel = 1e-12, abs = 1e-12)
}
emit("sampling_srswr", "sampling", list(cases))
