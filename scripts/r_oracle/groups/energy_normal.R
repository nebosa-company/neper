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
# dcov.test: args (seed, reps, n, dx, dy, x, y) under "dcovtest"; what is carried by the case name: "dcovtest_stat" and "dcovtest_p"
for (rep in 1:8) {
  n <- sample(12:30, 1); dx <- sample(1:2, 1); dy <- sample(1:2, 1); sd0 <- sample(1:100000, 1); R <- sample(c(50, 99, 199), 1)
  x <- matrix(rnorm(n * dx), n, dx); y <- matrix(rnorm(n * dy), n, dy) + runif(1, 0, 1.5) * x[, 1]
  set.seed(sd0); tt <- dcov.test(x, y, R = R)
  a <- c(sd0, R, n, dx, dy, as.vector(t(x)), as.vector(t(y)))
  cases[[length(cases) + 1]] <- case("dcovtest_stat", a, as.numeric(tt$statistic), rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("dcovtest_p", a, as.numeric(tt$p.value), rel = 1e-12, abs = 1e-12)
}
emit("energy_normal", "energy", list(cases))
