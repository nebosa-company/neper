# ape::read.tree from a Newick string, then two summaries the row compares: the tips' patristic
# distances (cophenetic.phylo) and the root-to-MRCA branch length of every tip pair
# (node.depth.edgelength of getMRCA).
#   inputs: the Newick text from write.tree
#   args: (n, kind) kind 0 cophenetic matrix, 1 MRCA branch lengths
#   want: the value at each position weighted by its 1-based position, accumulated in a double loop
suppressMessages(library(ape))
cases <- list()
wsum <- function(v) {
  s <- 0
  for (i in seq_along(v)) s <- s + v[i] * i
  s
}
add <- function(n, kind, text, want) cases[[length(cases) + 1]] <<- case("tree", c(n, kind), want,
                                                                        rel = 1e-12, abs = 1e-12, input = text)
set.seed(20270106)
for (rep in 1:25) {
  n <- sample(4:10, 1)
  tr <- if (rep %% 2 == 0) rtree(n) else rcoal(n)
  text <- write.tree(tr)
  # the text carries 10 significant digits, so compare against the tree read back from it
  tr <- read.tree(text = text)
  cop <- cophenetic.phylo(tr)
  add(n, 0, text, wsum(as.vector(t(cop))))
  de <- node.depth.edgelength(tr)
  pairs <- numeric(0)
  for (i in seq_len(n - 1)) for (j in (i + 1):n) pairs <- c(pairs, de[getMRCA(tr, c(i, j))])
  add(n, 1, text, wsum(pairs))
}
emit("ape_tree", "ape", list(cases))
