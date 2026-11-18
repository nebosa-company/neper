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
emit("gamlss_exgaus", "gamlss.dist", list(cases))
