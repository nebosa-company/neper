# sampling: cluster(data, "g", size, method = "srswor"/"systematic"/"poisson", pik) under set.seed, with cluster labels 1..K (K < 10). Args: (method 0 srswor 1 systematic 2 poisson, N, K, seed,
# size, g[N], pik[K]); kind 0 the number of selected units, kind 1 the sum of the selected unit numbers, kind 2 the sum of unit number times cluster (merge orders the rows within a cluster arbitrarily, so no positions).
suppressMessages(library(sampling))
cases <- list()
set.seed(20262325)
add <- function(args, kind, want) cases[[length(cases) + 1]] <<- case(paste0("cl", kind), args, want, rel = 1e-9, abs = 1e-12)
for (rep in 1:30) {
  method <- (rep - 1) %% 3; K <- sample(4:9, 1); N <- sample(25:60, 1); sd <- sample(1:100000, 1)
  g <- c(1:K, sample(1:K, N - K, replace = TRUE)); g <- sample(g)
  w <- round(runif(K, 0.5, 3), 3); size <- sample(2:(K - 1), 1)
  d <- data.frame(g = g)
  set.seed(sd)
  r <- tryCatch(suppressWarnings(cluster(d, "g", size = size, method = c("srswor", "systematic", "poisson")[method + 1], pik = w)), error = function(e) NULL)
  if (is.null(r)) next
  id <- if ("index" %in% names(r)) r$index else r$ID_unit
  args <- c(method, N, K, sd, size, g, w)
  add(args, 0, nrow(r)); add(args, 1, sum(id)); add(args, 2, sum(id * r[[1]]))
}
# srswr (method 3).
for (rep in 1:12) {
  K <- sample(4:9, 1); N <- sample(25:60, 1); sd <- sample(1:100000, 1)
  g <- c(1:K, sample(1:K, N - K, replace = TRUE)); g <- sample(g)
  w <- round(runif(K, 0.5, 3), 3); size <- sample(2:(K - 1), 1)
  set.seed(sd)
  r <- tryCatch(suppressWarnings(cluster(data.frame(g = g), "g", size = size, method = "srswr")), error = function(e) NULL)
  if (is.null(r)) next
  args <- c(3, N, K, sd, size, g, w)
  add(args, 0, nrow(r)); add(args, 1, sum(r$ID_unit)); add(args, 2, sum(r$ID_unit * r[[1]]))
}
emit("sampling_cluster", "sampling", list(cases))
