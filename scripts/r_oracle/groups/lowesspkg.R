# lowesspkg: stats::lowess on sorted x.
#   args: (f, iter, delta, index, n, x (n, ascending), y (n)) answering lowess(x, y, f, iter, delta)$y[index + 1]
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-11)
set.seed(20262022)
for (rep in 1:30) {
  n <- sample(15:80, 1); x <- sort(round(runif(n, 0, 10), 4)); x <- x + seq_len(n) * 1e-6; y <- round(sin(x) + rnorm(n, 0, 0.4) + (runif(n) < 0.05) * 3, 4)
  f <- sample(c(0.3, 0.5, 2 / 3, 0.9), 1); it <- sample(0:4, 1); dl <- if (rep %% 2 == 0) 0.01 * diff(range(x)) else 0
  l <- lowess(x, y, f = f, iter = it, delta = dl)
  for (i in sample(n, 6)) add("lowess", c(f, it, dl, i - 1, n, x, y), l$y[i])
}
emit("lowesspkg", "stats", list(cases))
