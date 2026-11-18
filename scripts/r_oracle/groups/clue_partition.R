# clue: Rand agreement and minimal Euclidean membership distance of hard partitions with classes 1..K (K the larger count).
# Args: (n, kx, ky, cx[n], cy[n], which): which 0 the Rand agreement, 1 the Euclidean dissimilarity.
suppressMessages(library(clue))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261240)
for (rep in 1:24) {
  n <- sample(8:40, 1); kx <- sample(2:4, 1); ky <- sample(2:4, 1)
  cx <- c(seq_len(kx), sample(seq_len(kx), n - kx, replace = TRUE))
  cy <- c(seq_len(ky), sample(seq_len(ky), n - ky, replace = TRUE))
  px <- as.cl_partition(factor(cx)); py <- as.cl_partition(factor(cy))
  base <- c(n, kx, ky, cx, cy)
  add("cl", c(base, 0), as.numeric(cl_agreement(px, py, method = "Rand")))
  add("cl", c(base, 1), as.numeric(cl_dissimilarity(px, py, method = "euclidean")))
}
emit("clue_partition", "clue", list(cases))
