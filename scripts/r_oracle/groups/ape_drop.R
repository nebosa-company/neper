# ape::drop.tip on a Newick tree: a node left with one child is collapsed and its branch length is added to
# that child's, and the surviving tips keep their order. Compared through cophenetic.phylo of the result.
#   inputs: the Newick text
#   args: (ntips_after, ndrop, drop_1 ... drop_ndrop) with 1-based tip positions
#   want: the patristic distance matrix of the dropped tree, row-major, weighted by position in a double loop
suppressMessages(library(ape))
cases <- list()
wsum <- function(v) {
  s <- 0
  for (i in seq_along(v)) s <- s + v[i] * i
  s
}
add <- function(args, text, want) cases[[length(cases) + 1]] <<- case("drop", args, want,
                                                                    rel = 1e-12, abs = 1e-12, input = text)
set.seed(20270107)
for (rep in 1:20) {
  n <- sample(5:10, 1)
  tr <- if (rep %% 2 == 0) rtree(n) else rcoal(n)
  text <- write.tree(tr)
  tr <- read.tree(text = text)
  nd <- sample(1:2, 1)
  idx <- sort(sample(n, nd))
  d <- drop.tip(tr, tr$tip.label[idx])
  cop <- cophenetic.phylo(d)
  add(c(Ntip(d), nd, idx), text, wsum(as.vector(t(cop))))
}
emit("ape_drop", "ape", list(cases))
