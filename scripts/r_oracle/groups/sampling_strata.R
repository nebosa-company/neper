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
emit("sampling_strata", "sampling", list(cases))
