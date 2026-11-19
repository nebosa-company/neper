# dagitty: ancestors, d-separation and minimal adjustment sets of random DAGs (nodes v1..vn, edges only from lower to higher index).
#   args: (n, x, y, zmask, adjacency row-major n by n...)   fn "dsep" (1 or 0), "anc" (ancestor mask of y, 0-based nodes), "nadj" (the number of minimal
#   adjustment sets for the total effect of x on y), "sadj" (the sum of their bit masks)
suppressMessages(library(dagitty))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-12, abs = 1e-12)
set.seed(20261212)
mask <- function(v, nodes) sum(2^(match(v, nodes) - 1))
for (rep in 1:40) {
  n <- sample(4:8, 1); nodes <- paste0("v", seq_len(n))
  A <- matrix(0, n, n); for (i in 1:(n - 1)) for (j in (i + 1):n) if (runif(1) < 0.4) A[i, j] <- 1
  edges <- which(A == 1, arr.ind = TRUE)
  txt <- paste("dag {", paste(nodes, collapse = " "), if (nrow(edges)) paste(sprintf("%s -> %s", nodes[edges[, 1]], nodes[edges[, 2]]), collapse = " "), "}")
  g <- dagitty(txt)
  flat <- as.vector(t(A))
  x <- sample(n - 1, 1); y <- sample((x + 1):n, 1)
  for (t in 1:4) {
    rest <- setdiff(seq_len(n), c(x, y)); z <- rest[runif(length(rest)) < 0.4]
    add("dsep", c(n, x - 1, y - 1, sum(2^(z - 1)), flat), as.numeric(dseparated(g, nodes[x], nodes[y], nodes[z])))
  }
  add("anc", c(n, x - 1, y - 1, 0, flat), mask(ancestors(g, nodes[y]), nodes))
  s <- adjustmentSets(g, nodes[x], nodes[y], type = "minimal", effect = "total")
  add("nadj", c(n, x - 1, y - 1, 0, flat), length(s))
  add("sadj", c(n, x - 1, y - 1, 0, flat), sum(vapply(s, function(v) if (length(v)) mask(v, nodes) else 0, 0)))
}
# more: "nall"/"sall" the number and mask sum of all valid adjustment sets (type = "all"), "canon" the canonical adjustment set's mask (-1 when dagitty answers none), "npaths"/"nopen" the
# number of paths between x and y and how many are open given the set zmask (args as above with zmask used)
for (rep in 1:40) {
  n <- sample(4:8, 1); nodes <- paste0("v", seq_len(n))
  A <- matrix(0, n, n); for (i in 1:(n - 1)) for (j in (i + 1):n) if (runif(1) < 0.4) A[i, j] <- 1
  edges <- which(A == 1, arr.ind = TRUE)
  txt <- paste("dag {", paste(nodes, collapse = " "), if (nrow(edges)) paste(sprintf("%s -> %s", nodes[edges[, 1]], nodes[edges[, 2]]), collapse = " "), "}")
  g <- dagitty(txt); flat <- as.vector(t(A))
  x <- sample(n - 1, 1); y <- if (x + 1 == n) n else sample((x + 1):n, 1)
  sa <- adjustmentSets(g, nodes[x], nodes[y], type = "all", effect = "total")
  add("nall", c(n, x - 1, y - 1, 0, flat), length(sa))
  add("sall", c(n, x - 1, y - 1, 0, flat), sum(vapply(sa, function(v) if (length(v)) mask(v, nodes) else 0, 0)))
  sc <- adjustmentSets(g, nodes[x], nodes[y], type = "canonical", effect = "total")
  add("canon", c(n, x - 1, y - 1, 0, flat), if (length(sc) == 0) -1 else if (length(sc[[1]])) mask(sc[[1]], nodes) else 0)
  for (t in 1:3) {
    rest <- setdiff(seq_len(n), c(x, y)); z <- rest[runif(length(rest)) < 0.4]
    pp <- paths(g, nodes[x], nodes[y], nodes[z])
    zz <- c(n, x - 1, y - 1, sum(2^(z - 1)), flat)
    add("npaths", zz, length(pp$paths)); add("nopen", zz, sum(unlist(pp$open)))
  }
}
# "neq": the number of DAGs in the Markov equivalence class (length(equivalentDAGs(g))), DAGs with at most 14 edges
for (rep in 1:40) {
  n <- sample(4:8, 1); nodes <- paste0("v", seq_len(n))
  A <- matrix(0, n, n); for (i in 1:(n - 1)) for (j in (i + 1):n) if (runif(1) < 0.35) A[i, j] <- 1
  edges <- which(A == 1, arr.ind = TRUE)
  if (nrow(edges) == 0 || nrow(edges) > 14) next
  txt <- paste("dag {", paste(nodes, collapse = " "), paste(sprintf("%s -> %s", nodes[edges[, 1]], nodes[edges[, 2]]), collapse = " "), "}")
  g <- dagitty(txt)
  add("neq", c(n, 0, 1, 0, as.vector(t(A))), length(equivalentDAGs(g)))
}
emit("dagitty", "dagitty", list(cases))
