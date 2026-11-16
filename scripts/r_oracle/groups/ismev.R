# ismev: stationary gev.fit, gpd.fit and gum.fit (Nelder-Mead MLE and the optim Hessian standard errors).
#   args: (kind, which, threshold, n, x...)   kind 0 gev 1 gpd 2 gum; which 0.. a parameter, 10.. its standard error, 99 the negative log-likelihood
#   fits agree to the optimiser tolerance of R, so the cases carry looser tolerances than the other groups
suppressMessages(library(ismev))
cases <- list()
add <- function(fn, args, want, rel) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-3)
set.seed(20261208)
for (rep in 1:9) {
  n <- sample(60:200, 1); u <- runif(n); xi <- c(0.2, -0.15, 0.05)[rep %% 3 + 1]; mu <- runif(1, 5, 20); sc <- runif(1, 1, 4)
  x <- mu + sc * ((-log(u))^(-xi) - 1) / xi
  f <- gev.fit(x, show = FALSE); p <- length(f$mle)
  for (k in 1:p) { add("fit", c(0, k - 1, 0, n, x), f$mle[k], 2e-2); add("fit", c(0, 10 + k - 1, 0, n, x), f$se[k], 5e-2) }
  add("fit", c(0, 99, 0, n, x), f$nllh, 1e-6)
  g <- gum.fit(x, show = FALSE)
  for (k in 1:2) { add("fit", c(2, k - 1, 0, n, x), g$mle[k], 2e-2); add("fit", c(2, 10 + k - 1, 0, n, x), g$se[k], 5e-2) }
  add("fit", c(2, 99, 0, n, x), g$nllh, 1e-6)
  w <- rexp(n) * 2 + (rep %% 2) * 0.3 * rexp(n)^2; th <- quantile(w, 0.6)
  h <- gpd.fit(w, th, show = FALSE)
  for (k in 1:2) { add("fit", c(1, k - 1, th, n, w), h$mle[k], 2e-2); add("fit", c(1, 10 + k - 1, th, n, w), h$se[k], 5e-2) }
  add("fit", c(1, 99, th, n, w), h$nllh, 1e-6)
}
emit("ismev", "ismev", list(cases))
