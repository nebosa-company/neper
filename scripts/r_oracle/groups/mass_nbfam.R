# MASS: negative.binomial(theta) family. Args: (y, mu, wt, theta): "nbvar", "nbdev", "nbaic".
suppressMessages(library(MASS))
cases <- list()
set.seed(20262380)
for (rep in 1:200) {
  y <- rpois(1, 3) * sample(1:2, 1); mu <- runif(1, 0.2, 9); wt <- round(runif(1, 0.5, 2), 2); th <- runif(1, 0.3, 12)
  f <- negative.binomial(th)
  a <- c(y, mu, wt, th)
  cases[[length(cases) + 1]] <- case("nbvar", a, f$variance(mu), rel = 1e-12, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("nbdev", a, f$dev.resids(y, mu, wt), rel = 1e-10, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("nbaic", a, f$aic(y, 1, mu, wt, 0), rel = 1e-9, abs = 1e-10)
}
emit("mass_nbfam", "MASS", list(cases))
