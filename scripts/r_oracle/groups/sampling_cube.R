# sampling::fastflightcube: args (N, p, order, seed, pik[N], X[N p] row-major); "cs" the position-weighted sum of the returned probabilities, "cf" the number still fractional
suppressMessages(library(sampling))
cases <- list()
set.seed(20271105)
for (rep in 1:30) {
  N <- sample(15:50, 1); p <- sample(1:3, 1); ord <- c(1, 1, 2, 3)[rep %% 4 + 1]; sd <- sample(1:100000, 1)
  pik <- inclusionprobabilities(runif(N) + 0.1, sample(4:min(10, N - 3), 1))
  X <- cbind(pik, matrix(rnorm(N * (p - 1)), N))[, seq_len(p), drop = FALSE]
  set.seed(sd); r <- fastflightcube(X, pik, order = ord, comment = FALSE)
  a <- c(N, p, ord, sd, pik, as.vector(t(X)))
  cases[[length(cases) + 1]] <- case("cs", a, sum(r * seq_along(r)), rel = 1e-8, abs = 1e-9)
  cases[[length(cases) + 1]] <- case("cf", a, sum(r > 1e-11 & r < 1 - 1e-11), rel = 0, abs = 0)
}
# samplecube (method 1): "sc" args as above; the sample's position-weighted sum and its size (flight phase, then the landing phase when probabilities stay fractional)
for (rep in 1:40) {
  N <- sample(15:50, 1); p <- sample(1:3, 1); ord <- c(1, 1, 2, 3)[rep %% 4 + 1]; sd <- sample(1:100000, 1)
  pik <- inclusionprobabilities(runif(N) + 0.1, sample(4:min(10, N - 3), 1))
  X <- cbind(pik, matrix(rnorm(N * (p - 1)), N))[, seq_len(p), drop = FALSE]
  set.seed(sd); s <- tryCatch(samplecube(X, pik, order = ord, comment = FALSE), error = function(e) NULL)
  if (is.null(s)) next
  a <- c(N, p, ord, sd, pik, as.vector(t(X)))
  cases[[length(cases) + 1]] <- case("ss", a, sum(s * seq_along(s)), rel = 0, abs = 0)
  cases[[length(cases) + 1]] <- case("sn", a, sum(s), rel = 0, abs = 0)
}
emit("sampling_cube", "sampling", list(cases))
