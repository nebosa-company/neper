# energy: energy.hclust. Args: (n, d, alpha, x row-major n * d): "height", "merge" and "order", each the sum of value * (position + 1).
suppressMessages(library(energy))
cases <- list()
set.seed(20262370)
for (rep in 1:30) {
  n <- sample(6:25, 1); d <- sample(1:3, 1); X <- matrix(round(rnorm(n * d) * 2, 3), n, d); alpha <- c(1, 0.5, 1.5, 2)[rep %% 4 + 1]
  h <- energy.hclust(dist(X), alpha = alpha)
  a <- c(n, d, alpha, as.vector(t(X)))
  cases[[length(cases) + 1]] <- case("height", a, sum(h$height * seq_along(h$height)), rel = 1e-9, abs = 1e-9)
  cases[[length(cases) + 1]] <- case("merge", a, sum(as.vector(t(h$merge)) * seq_len(length(h$merge))), rel = 1e-9, abs = 1e-9)
  cases[[length(cases) + 1]] <- case("order", a, sum(h$order * seq_along(h$order)), rel = 1e-9, abs = 1e-9)
}
emit("energy_hc", "energy", list(cases))
