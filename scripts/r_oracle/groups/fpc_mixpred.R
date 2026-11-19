# fpc: mixpredictive and mergenormals(method = "predictive") on mclust fits, under set.seed.
#   "mp": (seed, n, p, Gcomp, Gmix, M, what, idx, x n by p row-major): what 0 mean.pred, 1 predcorr[idx + 1]
#   "pr": (seed, n, p, G, cutoff, M, what, idx, x): mergenormals(x, Mclust(x, G = G), method = "predictive", cutoff, M): what 0 predvalues[idx + 1], 1 length(clusternumbers),
#         2 sum(mergedtonumbers * position), 3 sum(clustering * position)
suppressMessages(library(fpc)); suppressMessages(library(mclust))
cases <- list()
set.seed(20269991)
flat <- function(m) as.vector(t(unclass(as.matrix(m))))
add <- function(nm, args, want, rel = 1e-9, abs = 1e-11) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(nm, args, want, rel = rel, abs = abs)
mk <- function(n, p, k, sep) {
  cl <- sample(k, n, TRUE); mu <- matrix(rnorm(k * p) * sep, k, p)
  round(matrix(rnorm(n * p), n, p) + mu[cl, , drop = FALSE], 4)
}
for (rep in 1:8) {
  p <- c(2, 1, 2, 3)[rep %% 4 + 1]; n <- sample(50:70, 1); gc <- sample(3:4, 1); gm <- sample(2:(gc - 1), 1); M <- 4; seed <- sample(1:100000, 1)
  x <- mk(n, p, 3, 2.5)
  set.seed(seed); r <- mixpredictive(x, gc, gm, M)
  hd <- c(seed, n, p, gc, gm, M)
  add("mp", c(hd, 0, 0, flat(x)), r$mean.pred, 1e-9)
  for (l in 1:M) add("mp", c(hd, 1, l - 1, flat(x)), r$predcorr[l], 1e-9)
}
for (rep in 1:6) {
  p <- c(2, 1, 2)[rep %% 3 + 1]; n <- sample(50:70, 1); G <- sample(3:4, 1); M <- 4; seed <- sample(1:100000, 1); cutoff <- c(0.75, 0.5)[rep %% 2 + 1]
  x <- mk(n, p, 3, 3)
  mc <- Mclust(x, G = G, verbose = FALSE)
  set.seed(seed); r <- mergenormals(x, mc, method = "predictive", cutoff = cutoff, M = M)
  hd <- c(seed, n, p, G, cutoff, M)
  for (q in 1:G) add("pr", c(hd, 0, q - 1, flat(x)), r$predvalues[q], 1e-9)
  add("pr", c(hd, 1, 0, flat(x)), length(r$clusternumbers), 0, 0)
  add("pr", c(hd, 2, 0, flat(x)), sum(r$mergedtonumbers * seq_along(r$mergedtonumbers)), 0, 0)
  add("pr", c(hd, 3, 0, flat(x)), sum(r$clustering * seq_along(r$clustering)), 0, 0)
}
emit("fpc_mixpred", c("fpc", "mclust"), list(cases))
