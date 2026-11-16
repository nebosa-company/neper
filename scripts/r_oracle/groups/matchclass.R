# e1071::matchClasses (verbose = FALSE) under set.seed.
#   args: (seed, method 0 rowmax 1 greedy 2 exact, iter, maxexact, nr, nc, table row-major[nr*nc]); the answer is sum(i * match[i]) of the 1-based columns
suppressMessages(library(e1071))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("mc", args, want, rel = 1e-12, abs = 1e-12)
set.seed(20261117)
for (rep in 1:300) {
  method <- sample(0:2, 1)
  n <- sample(2:8, 1); nc <- if (method == 0) sample(2:8, 1) else n
  tab <- matrix(rpois(n * nc, sample(c(2, 5, 12), 1)), n, nc) + if (rep %% 2 == 0) diag(rpois(n, 10), n, nc) else 0
  if (rep %% 5 == 0) tab <- matrix(sample(0:3, n * nc, TRUE), n, nc)
  seed <- sample(1e6, 1); iter <- sample(1:4, 1); mx <- sample(c(9, 3), 1)
  set.seed(seed)
  r <- tryCatch(suppressWarnings(matchClasses(tab, c("rowmax", "greedy", "exact")[method + 1], iter = iter, maxexact = mx, verbose = FALSE)), error = function(e) NULL)
  if (is.null(r)) next
  add(c(seed, method, iter, mx, n, nc, as.vector(t(tab))), sum(seq_along(r) * as.numeric(r)))
}
emit("matchclass", "e1071", list(cases))
