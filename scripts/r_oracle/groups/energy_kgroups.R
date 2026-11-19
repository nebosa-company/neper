# energy kgroups from a given start: args (n, d, k, iter.max, cl0[n] 0-based, x[n*d] row-major); "it" iterations, "ct" moves in the last pass, "w" the objective W, "cl" the position-weighted sum of the 1-based clusters
suppressMessages(library(energy))
cases <- list()
set.seed(20271104)
for (rep in 1:40) {
  n <- sample(15:45, 1); d <- sample(1:3, 1); k <- sample(2:4, 1); itm <- c(10, 10, 3)[rep %% 3 + 1]
  x <- matrix(rnorm(n * d), n) + sample(0:3, n, TRUE) * 0.8
  cl0 <- sample(0:(k - 1), n, TRUE); if (length(unique(cl0)) < k) next
  r <- kgroups(x, k, iter.max = itm, cluster = factor(cl0))
  a <- c(n, d, k, itm, cl0, as.vector(t(x)))
  cases[[length(cases) + 1]] <- case("it", a, r$iterations, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("ct", a, r$count, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("w", a, r$W, rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("cl", a, sum(r$cluster * seq_along(r$cluster)), rel = 0, abs = 0)
}
# the random start: set.seed(seed) then kgroups(x, k, iter.max) draws cluster = sample(0:(k - 1), n, replace = TRUE) itself; the args carry the seed in place of the start: (n, d, k, iter.max, seed, x)
for (rep in 1:30) {
  n <- sample(15:45, 1); d <- sample(1:3, 1); k <- sample(2:4, 1); sd <- sample(1:100000, 1)
  x <- matrix(rnorm(n * d), n) + sample(0:3, n, TRUE) * 0.8
  set.seed(sd); r <- kgroups(x, k, iter.max = 10)
  a <- c(n, d, k, 10, sd, as.vector(t(x)))
  cases[[length(cases) + 1]] <- case("sit", a, r$iterations, rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("sw", a, r$W, rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("scl", a, sum(r$cluster * seq_along(r$cluster)), rel = 0, abs = 0)
}
emit("energy_kgroups", "energy", list(cases))
