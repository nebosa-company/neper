# sampling: UPmaxentropy(pik) under set.seed. Args: (N, n, seed, a[N]), pik = inclusionprobabilities(a, n); the position-weighted sample indicator.
suppressMessages(library(sampling))
cases <- list()
set.seed(20262332)
for (rep in 1:40) {
  N <- sample(6:25, 1); n <- sample(2:(N - 2), 1); sd <- sample(1:100000, 1); a <- round(runif(N, 0.1, 5) * c(1, 1, 6)[sample(3, N, replace = TRUE)], 4)
  pik <- inclusionprobabilities(a, n)
  set.seed(sd); s <- tryCatch(UPmaxentropy(pik), error = function(e) NULL); if (is.null(s)) next
  cases[[length(cases) + 1]] <- case("me", c(N, n, sd, a), sum(s * seq_len(N)), rel = 1e-12, abs = 1e-12)
}
emit("sampling_maxent", "sampling", list(cases))
