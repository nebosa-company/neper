# qgraph centrality_auto on random connected weighted undirected graphs.
#   args: (n, W[n*n] row-major symmetric)
#   fn "between" "closeness" "strength" "ei" (node values weighted by position)
suppressMessages(library(qgraph))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-10)
ws <- function(v) sum(v * seq_along(v))
set.seed(20270108)
cnt <- 0
while (cnt < 24) {
  n <- sample(4:12, 1); w <- matrix(0, n, n); w[upper.tri(w)] <- ifelse(runif(n * (n - 1) / 2) < 0.45, round(runif(n * (n - 1) / 2, -0.9, 0.9), 2), 0); w <- w + t(w)
  g <- w != 0; reach <- g; for (k in 1:n) reach <- reach | (reach %*% g > 0); diag(reach) <- TRUE
  if (!all(reach)) next
  ca <- centrality_auto(w)$node.centrality; cnt <- cnt + 1
  a <- c(n, as.vector(t(w)))
  add("between", a, ws(ca$Betweenness)); add("closeness", a, ws(ca$Closeness)); add("strength", a, ws(ca$Strength)); add("ei", a, ws(ca$ExpectedInfluence))
}
emit("qgraph", "qgraph", list(cases))
