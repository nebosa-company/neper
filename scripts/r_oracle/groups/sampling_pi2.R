# sampling: UPtillepi2, UPsystematicpi2 and varHT (methods 1 and 2). Args: (kind, N, n, i, j, a[N], y[N]), pik = inclusionprobabilities(a, n); kind 0 UPtillepi2[i, j], 1 UPsystematicpi2[i, j],
# 2 and 3 varHT(y, UPtillepi2(pik), method 1 and 2), 4 and 5 varHT(y, UPsystematicpi2(pik), method 1 and 2) (skipped when R's value is not finite).
suppressMessages(library(sampling))
cases <- list()
set.seed(20262323)
add <- function(args, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case("p2", args, want, rel = rel, abs = 1e-12)
for (rep in 1:20) {
  N <- sample(6:14, 1); n <- sample(2:(N - 2), 1); a <- round(runif(N, 0.5, 2), 4); y <- round(rnorm(N, 5, 2), 3)
  pik <- inclusionprobabilities(a, n); if (any(pik >= 1)) next
  base <- function(k, i = 0, j = 0) c(k, N, n, i, j, a, y)
  pt <- UPtillepi2(pik); ps <- UPsystematicpi2(pik)
  for (i in 1:min(N, 4)) for (j in 1:N) { add(base(0, i - 1, j - 1), pt[i, j]); add(base(1, i - 1, j - 1), ps[i, j]) }
  add(base(2), varHT(y, pt, 1)); add(base(3), varHT(y, pt, 2))
  v4 <- varHT(y, ps, 1); v5 <- varHT(y, ps, 2); if (is.finite(v4)) add(base(4), v4); if (is.finite(v5)) add(base(5), v5)
}
emit("sampling_pi2", "sampling", list(cases))
