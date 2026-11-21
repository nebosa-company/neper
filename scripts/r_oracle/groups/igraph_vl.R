# igraph sample_degseq(method = "vl"): the Viger-Latapy sampler of a connected simple graph with a given degree sequence (degrees above 100 take igraph hash-table adjacency).
# A graph is summarised as its edge count (what 0) or sum over edges i (1-based, igraph's edge order) of i * (from * n + to + 1), 0-based endpoints, smaller first (what 1).
#   fn "vl"; args: (what, seed, n, degrees [n])
suppressMessages(library(igraph))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 0, abs = 0)
summ <- function(g, what) {
  n <- vcount(g); e <- as_edgelist(g, names = FALSE) - 1
  e <- cbind(pmin(e[, 1], e[, 2]), pmax(e[, 1], e[, 2]))
  if (what == 0) return(nrow(e))
  sum(seq_len(nrow(e)) * (e[, 1] * n + e[, 2] + 1))
}
set.seed(20261124)
sd <- 9000
for (rep in 1:80) {
  n <- sample(5:40, 1)
  repeat { g <- if (rep %% 4 == 0) sample_pa(n, m = 1, directed = FALSE) else if (rep > 40) sample_gnp(n, runif(1, 1.2, 3) / n) else sample_gnp(n, runif(1, 0.1, 0.5)); if (is_connected(g)) break }
  dg <- degree(g)
  sd <- sd + 1
  for (what in 0:1) { set.seed(sd); add("vl", c(what, sd, n, dg), summ(sample_degseq(dg, method = "vl"), what)) }
}
# hubs of degree above 100 (igraph keeps their neighbours in an open-addressing table)
for (rep in 1:14) {
  n <- sample(130:320, 1)
  hubs <- if (rep %% 3 == 0) 1:2 else 1
  repeat {
    g <- sample_gnp(n, runif(1, 1.5, 3) / n)
    for (h in hubs) { k <- sample(101:min(n - 1, 100 + sample(5:120, 1)), 1); tg <- sample(setdiff(1:n, h), k); g <- add_edges(g, as.vector(rbind(h, tg))); g <- simplify(g) }
    if (is_connected(g) && max(degree(g)) > 100) break
  }
  dg <- degree(g)
  sd <- sd + 1
  for (what in 0:1) { set.seed(sd); add("vl", c(what, sd, n, dg), summ(sample_degseq(dg, method = "vl"), what)) }
}
emit("igraph_vl", "igraph", list(cases))
