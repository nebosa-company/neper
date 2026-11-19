# sampling: UPtillepi2, UPsystematicpi2 and varHT (methods 1 and 2). Args: (kind, N, n, i, j, a[N], y[N]), pik = inclusionprobabilities(a, n); kind 0 UPtillepi2[i, j], 1 UPsystematicpi2[i, j],
# 12 UPmaxentropypi2[i, j]; 9 UPsampfordpi2[i, j], 10 and 11 varHT of it; 6 UPmidzunopi2[i, j], 7 and 8 varHT of it (methods 1 and 2); 2 and 3 varHT(y, UPtillepi2(pik), method 1 and 2), 4 and 5 varHT(y, UPsystematicpi2(pik), method 1 and 2) (skipped when R's value is not finite).
suppressMessages(library(sampling))
cases <- list()
set.seed(20262323)
add <- function(args, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case("p2", args, want, rel = rel, abs = 1e-12)
for (rep in 1:20) {
  N <- sample(6:14, 1); n <- sample(2:(N - 2), 1); a <- round(runif(N, 0.5, 2), 4); y <- round(rnorm(N, 5, 2), 3)
  pik <- inclusionprobabilities(a, n); if (any(pik >= 1)) next
  base <- function(k, i = 0, j = 0) c(k, N, n, i, j, a, y)
  pt <- UPtillepi2(pik); ps <- UPsystematicpi2(pik); pm <- UPmidzunopi2(pik); pf <- tryCatch(UPsampfordpi2(pik), error = function(e) NULL); pe <- tryCatch(UPmaxentropypi2(pik), error = function(e) NULL)
  for (i in 1:min(N, 4)) for (j in 1:N) { add(base(0, i - 1, j - 1), pt[i, j]); add(base(1, i - 1, j - 1), ps[i, j]) }
  if (!is.null(pf)) { for (i in 1:min(N, 4)) for (j in 1:N) add(base(9, i - 1, j - 1), pf[i, j]); add(base(10), varHT(y, pf, 1)); add(base(11), varHT(y, pf, 2)) }
  if (!is.null(pe)) { for (i in 1:min(N, 4)) for (j in 1:N) add(base(12, i - 1, j - 1), pe[i, j]) }
  for (i in 1:min(N, 4)) for (j in 1:N) add(base(6, i - 1, j - 1), pm[i, j]); if (min(pm) > 1e-3) { add(base(7), varHT(y, pm, 1)); add(base(8), varHT(y, pm, 2)) }
  add(base(2), varHT(y, pt, 1)); add(base(3), varHT(y, pt, 2))
  v4 <- varHT(y, ps, 1); v5 <- varHT(y, ps, 2); if (is.finite(v4)) add(base(4), v4); if (is.finite(v5)) add(base(5), v5)
}
emit("sampling_pi2", "sampling", list(cases))
