# energy::normal.e (d = 1) and mvnorm.e (d >= 2): args (n, d, x row-major)
suppressMessages(library(energy)); suppressMessages(library(gsl))
cases <- list()
set.seed(20262301)
for (rep in 1:12) {
  d <- sample(1:4, 1); n <- sample(15:60, 1)
  x <- matrix(rnorm(n * d), n, d) + matrix(rexp(n * d), n, d) * runif(1, 0, 1)
  v <- mvnorm.e(if (d == 1) as.vector(x) else x)
  cases[[length(cases) + 1]] <- case("m", c(n, d, as.vector(t(x))), v, rel = 1e-8, abs = 1e-11)
}
emit("energy_normal", "energy", list(cases))
