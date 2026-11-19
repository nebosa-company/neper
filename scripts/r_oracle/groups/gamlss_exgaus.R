# gamlss.dist exGAUS (dexGAUS and pexGAUS with mu, sigma, nu). Args: (fn, mu, sigma, nu, x, which): fn 0 density, 1 distribution.
suppressMessages(library(gamlss.dist))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261245)
for (rep in 1:30) {
  mu <- rnorm(1, 2, 2); sg <- runif(1, 0.3, 2.5); nu <- runif(1, 0.1, 3) * (if (rep %% 3 == 0) 0.1 else 1)
  x <- rnorm(1, mu, sg + nu)
  add("eg", c(0, mu, sg, nu, x, 0), dexGAUS(x, mu = mu, sigma = sg, nu = nu))
  add("eg", c(1, mu, sg, nu, x, 0), pexGAUS(x, mu = mu, sigma = sg, nu = nu))
}
# fn 2: qexGAUS(p) (the argument x slot holds p); uniroot at eps^0.25, so a looser tolerance than the closed forms
set.seed(20262420)
for (rep in 1:60) {
  mu <- rnorm(1, 2, 2); sg <- runif(1, 0.3, 2.5); nu <- runif(1, 0.1, 3) * (if (rep %% 3 == 0) 0.1 else 1); p <- runif(1, 0.01, 0.99)
  add("eg", c(2, mu, sg, nu, p, 0), qexGAUS(p, mu = mu, sigma = sg, nu = nu), rel = 1e-9, abs = 1e-10)
}
emit("gamlss_exgaus", "gamlss.dist", list(cases))
