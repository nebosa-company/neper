# sampling: UPmultinomial(pik) under set.seed (R's inversion rbinom: sum(pik) * min(p, 1 - p) < 30). Args: (N, n, seed, a[N]), pik = inclusionprobabilities(a, n); the position-weighted counts.
suppressMessages(library(sampling))
cases <- list()
set.seed(20262331)
for (rep in 1:40) {
  N <- sample(8:40, 1); n <- sample(2:min(25, N %/% 2), 1); sd <- sample(1:100000, 1); a <- round(runif(N, 0.1, 5) * c(1, 1, 8)[sample(3, N, replace = TRUE)], 4)
  pik <- inclusionprobabilities(a, n)
  set.seed(sd); s <- tryCatch(UPmultinomial(pik), error = function(e) NULL); if (is.null(s)) next
  cases[[length(cases) + 1]] <- case("um", c(N, n, sd, a), sum(s * seq_len(N)), rel = 1e-12, abs = 1e-12)
}
emit("sampling_mult", "sampling", list(cases))
