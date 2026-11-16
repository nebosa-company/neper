# catoolspkg: caTools running-window statistics with their default end rules (shrinking windows), odd k.
#   args: (stat 0 runmean 1 runmin 2 runmax 3 runsd 4 runquantile, k, p, index, n, x...)
suppressMessages(library(caTools))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20262024)
for (rep in 1:30) {
  n <- sample(12:60, 1); x <- round(rnorm(n, 2, 3), 4); k <- sample(c(3, 5, 7, 9), 1); p <- sample(c(0.1, 0.25, 0.5, 0.9), 1)
  r <- list(runmean(x, k), runmin(x, k), runmax(x, k), runsd(x, k), as.vector(runquantile(x, k, p)))
  for (s in 0:4) for (i in sample(n, 5)) add("run", c(s, k, p, i - 1, n, x), r[[s + 1]][i])
}
emit("catoolspkg", "caTools", list(cases))
