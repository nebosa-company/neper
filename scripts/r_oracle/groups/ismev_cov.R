# ismev: gev.fit with a location covariate (ydat = z, mul = 1). Args: (which, n, x[n], z[n]); which 0 and 1 the location coefficients, 2 the scale,
# 3 the shape, 10 + k their standard errors, 99 the negative log-likelihood. Fits agree to the optimiser tolerance of R (looser tolerances).
suppressMessages(library(ismev))
cases <- list()
add <- function(fn, args, want, rel) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-3)
set.seed(20261233)
for (rep in 1:9) {
  n <- sample(80:200, 1); z <- runif(n); u <- runif(n)
  xi <- c(0.1, -0.1, 0.2)[rep %% 3 + 1]; sc <- runif(1, 1, 3)
  mu <- 5 + 3 * z; x <- mu + sc * ((-log(u))^(-xi) - 1) / xi
  f <- gev.fit(x, ydat = cbind(z), mul = 1, show = FALSE)
  for (k in 1:4) { add("mf", c(k - 1, n, x, z), f$mle[k], 2e-2); add("mf", c(k - 1 + 10, n, x, z), f$se[k], 5e-2) }
  add("mf", c(99, n, x, z), f$nllh, 1e-6)
}
emit("ismev_cov", "ismev", list(cases))
