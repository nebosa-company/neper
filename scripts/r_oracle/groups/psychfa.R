# psych::fa(r, nfactors = q, n.obs, fm = "ml", rotate = "none"): "faml" args (p, q, r[p * p] row-major, k) k 0 .. p - 1 the uniquenesses, p the factanal objective at the optimum
suppressMessages(library(psych))
cases <- list()
set.seed(20271221)
for (rep in 1:12) {
  p <- sample(5:8, 1); q <- sample(1:2, 1); N <- sample(200:400, 1)
  L <- matrix(runif(p * q, 0.3, 0.8), p, q); Fm <- matrix(rnorm(N * q), N, q); X <- Fm %*% t(L) + matrix(rnorm(N * p, 0, 0.7), N, p)
  R <- cor(X)
  f <- tryCatch(suppressWarnings(fa(R, nfactors = q, n.obs = N, fm = "ml", rotate = "none")), error = function(e) NULL)
  if (is.null(f)) next
  u <- f$uniquenesses; if (any(u < 0.02)) next
  for (k in 1:p) cases[[length(cases) + 1]] <- case("faml", c(p, q, as.vector(t(R)), k - 1), as.numeric(u[k]), rel = 1e-3, abs = 1e-4)
}
emit("psychfa", "psych", list(cases))
