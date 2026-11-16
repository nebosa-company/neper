# rdensity: stats::density with the Gaussian kernel.
#   args: (bw or 0 for bw.nrd0, nout, index, nx, x...) answering density(x, bw, n = nout)$y[index + 1]; bw.nrd0 itself is "bw" (0, 0, 0, nx, x...)
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-13)
set.seed(20262015)
for (rep in 1:20) {
  n <- sample(30:300, 1); x <- round(if (rep %% 3 == 0) rgamma(n, 2) else rnorm(n, runif(1, -1, 1), runif(1, 0.5, 2)), 5)
  add("bw", c(0, 0, 0, n, x), bw.nrd0(x))
  bw <- if (rep %% 2 == 0) 0 else runif(1, 0.1, 0.8); nout <- sample(c(512, 200, 1000), 1)
  d <- if (bw == 0) density(x, n = nout) else density(x, bw = bw, n = nout)
  for (i in sample(nout, 6)) add("dens", c(bw, nout, i - 1, n, x), d$y[i])
}
emit("rdensity", "stats", list(cases))
