# igraph random graph generators under set.seed: sample_gnp, sample_gnm, sample_sbm, sample_pa, sample_smallworld (dim 1),
# sample_degseq (configuration) and sample_k_regular. Every case is one graph summarised as its edge count (what 0) or
# sum over edges i (1-based, igraph's edge order) of i * (from * n + to + 1), 0-based endpoints, undirected edges as (smaller, larger) (what 1).
#   args: (what, seed, ...) per fn: "gnp" (n, p, directed, loops); "gnm" (n, m, directed, loops); "sbm" (n, directed, loops, k, block sizes[k], pref[k*k]);
#   "pa" (n, power, m, outpref, A, directed, algo 0 psumtree 1 psumtree-multiple 2 bag, hasseq, seq[n] when hasseq);
#   "sw" (size, nei, p, loops, multiple); "degseq" (n, directed, out[n], in[n] when directed); "kreg" (n, k, directed, multiple)
suppressMessages(library(igraph))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 0, abs = 0)
summ <- function(g, what) {
  n <- vcount(g); e <- as_edgelist(g, names = FALSE) - 1
  if (!is_directed(g) && nrow(e) > 0) e <- cbind(pmin(e[, 1], e[, 2]), pmax(e[, 1], e[, 2]))
  if (what == 0) return(nrow(e))
  if (nrow(e) == 0) return(0)
  sum(seq_len(nrow(e)) * (e[, 1] * n + e[, 2] + 1))
}
both <- function(fn, hdr, seed, gen) {
  for (what in 0:1) { set.seed(seed); add(fn, c(what, seed, hdr), summ(gen(), what)) }
}
set.seed(20261120)
sd <- 1000
nxt <- function() { sd <<- sd + 1; sd }
for (d in c(FALSE, TRUE)) for (lp in c(FALSE, TRUE)) {
  for (rep in 1:6) {
    n <- sample(4:30, 1); p <- c(0.05, 0.2, 0.5, 0.9)[(rep - 1) %% 4 + 1]
    s <- nxt(); both("gnp", c(n, p, d, lp), s, function() sample_gnp(n, p, directed = d, loops = lp))
    me <- n * (if (d) (if (lp) n else n - 1) else (if (lp) (n + 1) / 2 else (n - 1) / 2))
    m <- c(1, sample(2:max(2, me - 1), 1), sample(2:max(2, me - 1), 1), me)[(rep - 1) %% 4 + 1]
    s <- nxt(); both("gnm", c(n, m, d, lp), s, function() sample_gnm(n, m, directed = d, loops = lp))
  }
  both("gnp", c(9, 1, d, lp), nxt(), function() sample_gnp(9, 1, directed = d, loops = lp))
}
for (d in c(FALSE, TRUE)) for (lp in c(FALSE, TRUE)) for (rep in 1:6) {
  k <- sample(2:4, 1); bs <- sample(2:9, k, replace = TRUE); n <- sum(bs)
  P <- matrix(runif(k * k), k, k); if (!d) P[lower.tri(P)] <- t(P)[lower.tri(P)]
  P[sample(k * k, 1)] <- 0; if (!d) P[lower.tri(P)] <- t(P)[lower.tri(P)]
  s <- nxt(); both("sbm", c(n, d, lp, k, bs, as.vector(t(P))), s, function() sample_sbm(n, P, bs, directed = d, loops = lp))
}
for (rep in 1:48) {
  n <- sample(5:40, 1); algo <- (rep - 1) %% 3; m <- sample(1:3, 1)
  pw <- if (algo == 2) 1 else c(1, 0.5, 1.5, 0)[sample(4, 1)]; A <- if (algo == 2) 1 else c(1, 2, 0.5)[sample(3, 1)]
  d <- rep %% 2 == 0; op <- (rep %/% 2) %% 2 == 0; hs <- rep > 36; sq <- if (hs) sample(0:3, n, replace = TRUE) else NULL
  if (!d) op <- TRUE
  alg <- c("psumtree", "psumtree-multiple", "bag")[algo + 1]
  s <- nxt(); both("pa", c(n, pw, m, op, A, d, algo, hs, sq), s, function() sample_pa(n, power = pw, m = if (hs) NULL else m, out.seq = sq, out.pref = op, zero.appeal = A, directed = d, algorithm = alg))
}
for (rep in 1:40) {
  size <- sample(8:40, 1); nei <- sample(1:3, 1); p <- c(0.05, 0.2, 0.5, 1)[(rep - 1) %% 4 + 1]
  lp <- rep %% 2 == 0; mu <- (rep %/% 2) %% 2 == 0
  s <- nxt(); both("sw", c(size, nei, p, lp, mu), s, function() sample_smallworld(1, size, nei, p, loops = lp, multiple = mu))
}
for (rep in 1:16) {
  n <- sample(6:30, 1); d <- rep %% 2 == 0
  od <- sample(0:4, n, replace = TRUE); if (sum(od) %% 2 == 1) od[1] <- od[1] + 1
  id <- sample(od)
  s <- nxt()
  if (d) both("degseq", c(n, 1, od, id), s, function() sample_degseq(od, id, method = "configuration"))
  else both("degseq", c(n, 0, od), s, function() sample_degseq(od, method = "configuration"))
}
for (rep in 1:24) {
  n <- sample(6:30, 1); k <- sample(1:4, 1); d <- rep %% 2 == 0; mu <- (rep %/% 2) %% 2 == 0
  if (!d && (n * k) %% 2 == 1) n <- n + 1
  s <- nxt(); both("kreg", c(n, k, d, mu), s, function() sample_k_regular(n, k, directed = d, multiple = mu))
}
emit("igraph_games", "igraph", list(cases))
