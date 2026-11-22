# ape::dist.dna with global deletion (pairwise.deletion = FALSE, the default): raw, JC69, K80 and F81.
#   args: (n, l, model, x[n*l] row-major DNA codes 0..3 = A C G T, 4 = unknown or gap)
#   fn "dna": the sum over the n by n matrix of value * (row * n + col + 1), row by row, accumulated in a
#   double loop
suppressMessages(library(ape))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("dna", args, want, rel = 1e-12, abs = 1e-14)
wsum <- function(m) {
  v <- as.vector(t(m))
  s <- 0
  for (i in seq_along(v)) s <- s + v[i] * i
  s
}
set.seed(20270105)
letters <- c("a", "c", "g", "t")
for (rep in 1:25) {
  n <- sample(4:8, 1); L <- sample(20:60, 1)
  anc <- sample(0:3, L, replace = TRUE)
  codes <- matrix(0L, n, L)
  for (i in seq_len(n)) {
    row <- anc
    for (s in seq_len(L)) {
      if (runif(1) < 0.25) {
        # a transition (A<->G, C<->T) is more likely than a transversion, so K80 has signal
        row[s] <- if (runif(1) < 0.6) bitwXor(row[s], 2L) else sample(setdiff(0:3, row[s]), 1)
      }
    }
    codes[i, ] <- row
  }
  # unknown or gap bases at a few sites, which global deletion removes for every pair
  nbad <- sample(0:4, 1)
  if (nbad > 0) for (k in seq_len(nbad)) codes[sample(n, 1), sample(L, 1)] <- 4L
  ch <- matrix(letters[pmin(codes, 3L) + 1L], n, L)
  ch[codes == 4L] <- sample(c("n", "-"), sum(codes == 4L), replace = TRUE)
  db <- as.DNAbin(ch)
  for (model in c("raw", "JC69", "K80", "F81")) {
    d <- tryCatch(as.matrix(dist.dna(db, model = model, pairwise.deletion = FALSE)), error = function(e) NULL)
    if (is.null(d) || any(!is.finite(d))) next
    add(c(n, L, match(model, c("raw", "JC69", "K80", "F81")) - 1L, as.vector(t(codes))), wsum(d))
  }
}
emit("ape_dna", "ape", list(cases))
