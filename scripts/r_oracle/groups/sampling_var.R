# sampling: varest (without and with covariates) and vartaylor_ratio. Args: (kind, n, p, i, y[n], pik[n], x[n * p] row-major, w[n]) for kind 0 varest(y, pik = pik), 1 varest(y, Xs, pik, w);
# kind 2 vartaylor_ratio(y, x1, pikl) uses (2, n, 0, which, y, x1, pikl[n * n]) and answers the ratio (which 0) or the variance (which 1).
suppressMessages(library(sampling))
cases <- list()
set.seed(20262328)
add <- function(args, want) cases[[length(cases) + 1]] <<- case("va", args, want, rel = 1e-9, abs = 1e-12)
for (rep in 1:20) {
  n <- sample(10:30, 1); y <- round(rnorm(n, 20, 5), 3); pik <- round(runif(n, 0.2, 0.8), 3); p <- sample(1:3, 1)
  X <- matrix(round(runif(n * p, 1, 9), 3), n); w <- round(runif(n, 0.5, 2), 3)
  add(c(0, n, 0, 0, y, pik), varest(y, pik = pik))
  add(c(1, n, p, 0, y, pik, as.vector(t(X)), w), as.vector(varest(y, X, pik, w)))
  N <- n; pk <- UPtillepi2(inclusionprobabilities(round(runif(n, 1, 3), 3), 3)); if (any(diag(pk) <= 0)) next
  pk2 <- pk; yy <- y[1:n]; xx <- round(runif(n, 1, 9), 3)
  vr <- vartaylor_ratio(yy, xx, pk2)
  add(c(2, n, 0, 0, yy, xx, as.vector(t(pk2))), vr$ratio); add(c(2, n, 0, 1, yy, xx, as.vector(t(pk2))), vr$estvar)
}
emit("sampling_var", "sampling", list(cases))
