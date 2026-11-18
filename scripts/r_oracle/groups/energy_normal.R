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
# pdcor: args (n, dx, dy, dz, x, y, z row-major) under "pdcor"
for (rep in 1:10) {
  n <- sample(20:50, 1); dx <- sample(1:3, 1); dy <- sample(1:3, 1); dz <- sample(1:2, 1)
  z <- matrix(rnorm(n * dz), n, dz)
  x <- matrix(rnorm(n * dx), n, dx) + z[, 1]; y <- matrix(rnorm(n * dy), n, dy) + 0.5 * z[, 1]
  cases[[length(cases) + 1]] <- case("pdcor", c(n, dx, dy, dz, as.vector(t(x)), as.vector(t(y)), as.vector(t(z))), as.numeric(pdcor(x, y, z)), rel = 1e-8, abs = 1e-11)
}
emit("energy_normal", "energy", list(cases))
