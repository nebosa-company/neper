# sm.ancova p-values, models equal and parallel, with one or two covariates, unbinned or binned within each group.
#   "anc": (n, kind 0 equal 1 parallel, ndim, nbins, h1, h2, x1[n], x2[n] (zeros for one covariate), y[n], group[n])
suppressMessages(library(sm))
cases <- list()
set.seed(20262611)
add <- function(n, kind, ndim, nb, h1, h2, x1, x2, y, g, rel) {
  x <- if (ndim == 1) x1 else cbind(x1, x2); h <- if (ndim == 1) h1 else c(h1, h2)
  r <- tryCatch(sm.ancova(x, y, g, h = h, model = c("equal", "parallel")[kind + 1], display = "none", verbose = 0, nbins = nb)$p, error = function(e) NULL)
  if (!is.null(r) && is.finite(r)) cases[[length(cases) + 1]] <<- case("anc", c(n, kind, ndim, nb, h1, h2, x1, x2, y, g), r, rel = rel, abs = 1e-12)
}
for (rep in 1:60) {
  ndim <- 1 + (rep %% 2); nb <- if (rep %% 4 >= 2) sample(8:14, 1) else 0
  n <- if (nb > 0) sample(80:160, 1) else sample(24:50, 1)
  ng <- sample(2:3, 1); g <- sample(1:ng, n, TRUE); if (length(unique(g)) < ng) next
  x1 <- runif(n, 0, 10); x2 <- if (ndim == 2) runif(n, 0, 5) else rep(0, n)
  y <- sin(x1) + 0.3 * (g - 1) * (rep %% 3 == 0) + 0.2 * x2 + rnorm(n, 0, 0.3)
  h1 <- runif(1, 0.8, 1.8); h2 <- runif(1, 0.6, 1.4)
  for (kind in 0:1) add(n, kind, ndim, nb, h1, h2, x1, x2, y, g, 1e-10)
}
emit("sm_anc", "sm", list(cases))
