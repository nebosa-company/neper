# sna centrality indices of a random digraph.
#   args: (n, g[n*n] row-major)
#   fn: "outdeg" "indeg" "degree" "between" "stress" "closeness" "graphcent" "evcent" (weighted by position), "gden", "cent_degree" "cent_between" "cent_closeness"
suppressMessages(library(sna))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-7, abs = 1e-9)
ws <- function(v) sum(as.vector(v) * seq_along(v))
set.seed(20261229)
for (rep in 1:24) {
  n <- sample(5:20, 1); g <- matrix(rbinom(n * n, 1, runif(1, 0.12, 0.4)), n); diag(g) <- 0
  if (sum(g) == 0) g[1, 2] <- 1
  a <- c(n, as.vector(t(g)))
  add("outdeg", a, ws(degree(g, cmode = "outdegree"))); add("indeg", a, ws(degree(g, cmode = "indegree"))); add("degree", a, ws(degree(g)))
  add("between", a, ws(betweenness(g))); add("stress", a, ws(stresscent(g))); add("closeness", a, ws(closeness(g))); add("graphcent", a, ws(graphcent(g)))
  mv <- sort(Mod(eigen(g)$values), decreasing = TRUE)
  if (connectedness(g) == 1 && mv[1] - mv[2] > 1e-6) { ec <- evcent(g); if (all(is.finite(ec))) add("evcent", a, ws(abs(ec))) }
  add("gden", a, gden(g)); add("cent_degree", a, centralization(g, degree)); add("cent_between", a, centralization(g, betweenness)); add("cent_closeness", a, centralization(g, closeness))
}
emit("sna", "sna", list(cases))
