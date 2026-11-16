# parzen: modeest::parzen with the Gaussian kernel (statip's densityfun and optimize). The optimum of a flat density is found to optimize's tolerance (about 1e-4), and the FFT and the direct sum differ in the last bits, so the comparison is at rel 1e-5.
#   args: (bw or 0 for nrd0, n, x...)
suppressMessages(library(modeest))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-5, abs = 1e-6)
set.seed(20262030)
for (rep in 1:30) {
  n <- sample(15:120, 1); x <- round(if (rep %% 3 == 0) c(rnorm(n %/% 2, 0, 1), rnorm(n - n %/% 2, 4, 1.3)) else rgamma(n, 3, 1), 3); bw <- if (rep %% 2 == 0) 0 else runif(1, 0.3, 1)
  m <- if (bw == 0) parzen(x) else parzen(x, bw = bw)
  add("parzen", c(bw, length(x), x), m)
}
emit("parzen", "modeest", list(cases))
