# sampling: strata(data, "g", size, method = "srswor"/"systematic"/"poisson", pik) under set.seed. Args: (method 0 srswor 1 systematic 2 poisson, N, K strata, seed, size[K] in order of first
# appearance, g[N] labels, w[N]); the answers are the number of selected units (kind 0 in the result) and the sum over the selected ID_unit values weighted by position (kind 1).
suppressMessages(library(sampling))
cases <- list()
set.seed(20262324)
add <- function(args, kind, want) cases[[length(cases) + 1]] <<- case(paste0("st", kind), args, want, rel = 1e-9, abs = 1e-12)
for (rep in 1:30) {
  method <- (rep - 1) %% 3; K <- sample(2:4, 1); N <- sample(20:50, 1); sd <- sample(1:100000, 1)
  g <- sample(1:K, N, replace = TRUE); if (length(unique(g)) < K) next
  d <- data.frame(g = g, w = round(runif(N, 0.5, 3), 3)); order_first <- unique(g)
  sz <- vapply(order_first, function(l) sample(2:max(2, sum(g == l) %/% 2), 1), 1)
  if (method == 0 && any(sz > tabulate(g)[order_first])) next
  set.seed(sd)
  r <- tryCatch(suppressWarnings(strata(d, "g", size = sz, method = c("srswor", "systematic", "poisson")[method + 1], pik = d$w)), error = function(e) NULL)
  if (is.null(r)) next
  args <- c(method, N, K, sd, sz, g, d$w)
  add(args, 0, nrow(r)); add(args, 1, sum(r$ID_unit * seq_len(nrow(r))))
}
# srswr (method 3): sizes small enough for R's inversion binomial sampler.
for (rep in 1:12) {
  K <- sample(2:4, 1); N <- sample(30:60, 1); sd <- sample(1:100000, 1)
  g <- sample(1:K, N, replace = TRUE); if (length(unique(g)) < K) next
  d <- data.frame(g = g, w = round(runif(N, 0.5, 3), 3)); order_first <- unique(g)
  sz <- vapply(order_first, function(l) sample(2:min(12, sum(g == l)), 1), 1)
  set.seed(sd)
  r <- tryCatch(suppressWarnings(strata(d, "g", size = sz, method = "srswr")), error = function(e) NULL)
  if (is.null(r)) next
  args <- c(3, N, K, sd, sz, g, d$w)
  add(args, 0, nrow(r)); add(args, 1, sum(r$ID_unit * seq_len(nrow(r))))
}
# two stratification variables (srswor): the strata are the (a, b) combinations in order of first appearance; Neper takes the combined label 10 * a + b
set.seed(20262351)
for (rep in 1:20) {
  N <- sample(30:60, 1); sd <- sample(1:100000, 1)
  d <- data.frame(a = sample(1:2, N, TRUE), b = sample(1:3, N, TRUE), w = 1)
  code <- 10 * d$a + d$b; ord <- unique(code); K <- length(ord)
  sz <- vapply(ord, function(l) sample(1:max(1, sum(code == l) %/% 2), 1), 1)
  set.seed(sd)
  r <- tryCatch(suppressWarnings(strata(d, c("a", "b"), size = sz, method = "srswor")), error = function(e) NULL)
  if (is.null(r)) next
  args <- c(0, N, K, sd, sz, code, d$w)
  add(args, 0, nrow(r)); add(args, 1, sum(r$ID_unit * seq_len(nrow(r))))
}
emit("sampling_strata", "sampling", list(cases))
