# sampling: inclusion probabilities, the UP and SRS designs drawn under set.seed, and the Horvitz-Thompson estimator.
#   args: (kind, N, n, seed, a[N]...)   kind 0 inclusionprobabilities(a, n) -> sum of pik * position; 1 UPsystematic 2 UPpoisson 3 srswor 4 UPrandomsystematic 5 UPtille
#   (for 1, 2, 4, 5 the units' pik are inclusionprobabilities(a, n); the result is the sum of s * position); 6 HTestimator(y = a, pik = pik from n)
suppressMessages(library(sampling))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("s", args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261225)
for (rep in 1:30) {
  N <- sample(8:30, 1); n <- sample(3:(N %/% 2), 1); sd <- sample(1:100000, 1); a <- round(runif(N, 0.1, 5) * c(1, 1, 8)[sample(3, N, replace = TRUE)], 4)
  pik <- inclusionprobabilities(a, n)
  base <- function(k) c(k, N, n, sd, a)
  add(base(0), sum(pik * seq_len(N)))
  set.seed(sd); add(base(1), sum(UPsystematic(pik) * seq_len(N)))
  set.seed(sd); add(base(2), sum(UPpoisson(pik) * seq_len(N)))
  set.seed(sd); add(base(3), sum(srswor(n, N) * seq_len(N)))
  set.seed(sd); add(base(4), sum(UPrandomsystematic(pik) * seq_len(N)))
  if (all(pik < 1 - 1e-6)) { set.seed(sd); add(base(5), sum(UPtille(pik) * seq_len(N))) }
  add(base(6), as.numeric(HTestimator(a, pik)))
}
emit("sampling", "sampling", list(cases))
