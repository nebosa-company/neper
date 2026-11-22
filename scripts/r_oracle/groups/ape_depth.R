# ape::node.depth (the number of tips under each node) and ape::node.depth.edgelength (the root-to-node branch
# length), compared as order-free multisets because the node numbering differs between implementations.
#   inputs: the Newick text
#   args: (n, kind) kind 0 node.depth, 1 node.depth.edgelength
#   want: the sorted values weighted by their 1-based position, accumulated in a double loop
suppressMessages(library(ape))
cases <- list()
wsum <- function(v) {
  s <- 0
  for (i in seq_along(v)) s <- s + v[i] * i
  s
}
add <- function(n, kind, text, want) cases[[length(cases) + 1]] <<- case("depth", c(n, kind), want,
                                                                       rel = 1e-12, abs = 1e-12, input = text)
set.seed(20270108)
for (rep in 1:20) {
  n <- sample(4:10, 1)
  tr <- if (rep %% 2 == 0) rtree(n) else rcoal(n)
  text <- write.tree(tr)
  tr <- read.tree(text = text)
  add(n, 0, text, wsum(sort(node.depth(tr))))
  add(n, 1, text, wsum(sort(node.depth.edgelength(tr))))
}
emit("ape_depth", "ape", list(cases))
