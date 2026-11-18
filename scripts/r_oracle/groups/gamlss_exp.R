# gamlss.dist EXP (dEXP, pEXP, qEXP with mu). Args: (fn, mu, x, which): fn 0 density, 1 distribution, 2 quantile (x is p for 2).
suppressMessages(library(gamlss.dist))
cases <- list()
add <- function(fn, args, want, rel = 1e-10, abs = 1e-14) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261244)
for (rep in 1:30) {
  mu <- runif(1, 0.2, 8); x <- runif(1, 0, 6 * mu); p <- runif(1, 0.001, 0.999)
  add("ex", c(0, mu, x, 0), dEXP(x, mu = mu))
  add("ex", c(1, mu, x, 0), pEXP(x, mu = mu))
  add("ex", c(2, mu, p, 0), qEXP(p, mu = mu))
}
emit("gamlss_exp", "gamlss.dist", list(cases))
