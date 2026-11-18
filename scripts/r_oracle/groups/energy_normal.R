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
  set.seed(sd0); tc <- dcor.test(x, y, R = R)
  cases[[length(cases) + 1]] <- case("dcortest_stat", a, as.numeric(tc$statistic), rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("dcortest_p", a, as.numeric(tc$p.value), rel = 1e-12, abs = 1e-12)
}
# eqdist.etest with two samples: args (seed, reps, n1, n2, d, x row-major) under "eqtest_stat" and "eqtest_p"
for (rep in 1:8) {
  n1 <- sample(8:20, 1); n2 <- sample(8:20, 1); d <- sample(1:3, 1); sd0 <- sample(1:100000, 1); R <- sample(c(99, 199), 1)
  x <- rbind(matrix(rnorm(n1 * d), n1, d), matrix(rnorm(n2 * d, runif(1, 0, 0.8)), n2, d))
  set.seed(sd0); tt <- eqdist.etest(x, sizes = c(n1, n2), R = R)
  a <- c(sd0, R, n1, n2, d, as.vector(t(x)))
  cases[[length(cases) + 1]] <- case("eqtest_stat", a, as.numeric(tt$statistic), rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("eqtest_p", a, as.numeric(tt$p.value), rel = 1e-12, abs = 1e-12)
}
# eqdist.etest with three or four samples: args (seed, reps, k, sizes..., d, x row-major) under "keqtest_stat" and "keqtest_p"
for (rep in 1:8) {
  k <- sample(3:4, 1); sz <- sample(5:14, k, TRUE); d <- sample(1:3, 1); sd0 <- sample(1:100000, 1); R <- sample(c(99, 199), 1)
  x <- do.call(rbind, lapply(sz, function(m) matrix(rnorm(m * d, runif(1, 0, 0.8)), m, d)))
  set.seed(sd0); tt <- eqdist.etest(x, sizes = sz, R = R)
  a <- c(sd0, R, k, sz, d, as.vector(t(x)))
  cases[[length(cases) + 1]] <- case("keqtest_stat", a, as.numeric(tt$statistic), rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("keqtest_p", a, as.numeric(tt$p.value), rel = 1e-12, abs = 1e-12)
}
# disco, one factor: args (seed, reps, k, n, d, index, group codes 0-based..., x row-major) under "disco_b", "disco_w", "disco_f" and "disco_p"
for (rep in 1:8) {
  k <- sample(2:4, 1); n <- sample(12:30, 1); d <- sample(1:3, 1); sd0 <- sample(1:100000, 1); R <- sample(c(99, 199), 1); ix <- sample(c(1, 0.5, 1.5), 1)
  g <- c(0:(k - 1), sample(0:(k - 1), n - k, TRUE)); x <- matrix(rnorm(n * d, g * 0.4), n, d)
  set.seed(sd0); dd <- disco(x, factors = factor(g), index = ix, R = R)
  a <- c(sd0, R, k, n, d, ix, g, as.vector(t(x)))
  cases[[length(cases) + 1]] <- case("disco_b", a, as.numeric(dd$between), rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("disco_w", a, as.numeric(dd$within), rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("disco_f", a, as.numeric(dd$statistic), rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("disco_p", a, as.numeric(dd$p.value), rel = 1e-12, abs = 1e-12)
}
emit("energy_normal", "energy", list(cases))
