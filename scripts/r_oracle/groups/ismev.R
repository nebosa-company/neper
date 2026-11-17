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
# closed-form helpers: "h" (id, p1, p2, p3, p4[, p5]) id 0 gevq(mu, sigma, xi, p) 1 gevf(.., z) 2 gev.dens(.., z) 3 gpdq(sigma, xi, u, p) 4 gpdf(.., z) 5 gpd.dens(.., z) 6 gpdq2(sigma, xi, u, la, m)
# 7 gev.rl.gradient(a, p)[k] (sigma, xi, p, k) 8 gpd.rl.gradient(a = (la, sigma, xi), m)[k]
for (rep in 1:30) {
  mu <- rnorm(1); sg <- runif(1, 0.5, 2); xi <- if (rep %% 6 == 0) 0 else runif(1, -0.4, 0.5); a <- c(mu, sg, xi); p <- runif(1, 0.05, 0.95); z <- mu + sg * runif(1, -0.5, 3)
  hh <- function(id, ...) add2("h", c(id, ...), 0)
  add2 <- function(fn, args, want) NULL
  put <- function(id, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case("h", c(id, args), want, rel = 1e-9, abs = 1e-12)
  put(0, c(mu, sg, xi, p), gevq(a, p)); put(1, c(mu, sg, xi, z), gevf(a, z)); put(2, c(mu, sg, xi, z), gev.dens(a, z))
  if (xi != 0) { b <- c(sg, xi); u <- runif(1, 0, 2); zz <- u + runif(1, 0, 3); put(3, c(sg, xi, u, p), gpdq(b, u, p)); put(4, c(sg, xi, u, zz), gpdf(b, u, zz)); put(5, c(sg, xi, u, zz), gpd.dens(b, u, zz))
    la <- runif(1, 0.05, 0.5); m <- runif(1, 10, 500); put(6, c(sg, xi, u, la, m), gpdq2(b, u, la, m))
    for (k in 1:3) put(7, c(sg, xi, p, k - 1), gev.rl.gradient(a, p)[k, 1]); g <- gpd.rl.gradient(c(la, sg, xi), m); for (k in 1:3) put(8, c(la, sg, xi, m, k - 1), g[k, 1]) }
}
emit("ismev", "ismev", list(cases))
