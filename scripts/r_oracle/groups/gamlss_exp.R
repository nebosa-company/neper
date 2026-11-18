# gamlss.dist EXP (dEXP, pEXP, qEXP with mu) and RG (dRG, pRG, qRG with mu and sigma). Args: (fn, mu, sigma, x, which): fn 0 density, 1
# distribution, 2 quantile (x is p for 2); the family is EXP for fn 0..2 and RG for fn 3..5 (x is p for fn 5). sigma is unused by EXP.
suppressMessages(library(gamlss.dist))
cases <- list()
add <- function(fn, args, want, rel = 1e-10, abs = 1e-14) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261244)
for (rep in 1:30) {
  mu <- runif(1, 0.2, 8); x <- runif(1, 0, 6 * mu); p <- runif(1, 0.001, 0.999)
  sg <- runif(1, 0.3, 3); m2 <- rnorm(1)
  add("ex", c(0, mu, 1, x, 0), dEXP(x, mu = mu))
  add("ex", c(1, mu, 1, x, 0), pEXP(x, mu = mu))
  add("ex", c(2, mu, 1, p, 0), qEXP(p, mu = mu))
  add("ex", c(3, m2, sg, x, 0), dRG(x, mu = m2, sigma = sg))
  add("ex", c(4, m2, sg, x, 0), pRG(x, mu = m2, sigma = sg))
  add("ex", c(5, m2, sg, p, 0), qRG(p, mu = m2, sigma = sg))
}
emit("gamlss_exp", "gamlss.dist", list(cases))
