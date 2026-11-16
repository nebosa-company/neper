# parzen: modeest::parzen with the Gaussian kernel (statip's densityfun and optimize). The optimum of a flat density is found to optimize's tolerance (about 1e-4), and the FFT and the direct sum differ in the last bits, so the comparison is at rel 1e-5.
# naive picks the data points where the density is exactly maximal; R's FFT roundoff breaks ties that exact sums keep, so only cases with a unique maximum separated by 1e-9 are compared.
#   "parzen" (bw or 0 for nrd0, n, x...); "naive" (bw, n, x..., which 0 count 1 first mode)
suppressMessages(library(modeest))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-5, abs = 1e-6)
set.seed(20262030)
for (rep in 1:30) {
  n <- sample(15:120, 1); x <- round(if (rep %% 3 == 0) c(rnorm(n %/% 2, 0, 1), rnorm(n - n %/% 2, 4, 1.3)) else rgamma(n, 3, 1), 3); bw <- if (rep %% 2 == 0) 0 else runif(1, 0.3, 1)
  m <- if (bw == 0) parzen(x) else parzen(x, bw = bw)
  add("parzen", c(bw, length(x), x), m)
}
for (rep in 1:25) {
  n <- sample(15:100, 1); x <- round(if (rep %% 2 == 0) rnorm(n, 0, 1.3) else rgamma(n, 3, 1), 4); bw <- if (rep %% 3 == 0) 0.5 else runif(1, 0.3, 1.2)
  fx <- sort(statip::densityfun(x, bw = bw, kernel = "uniform")(x), decreasing = TRUE); if (length(fx) > 1 && fx[1] - fx[2] < 1e-9) next
  nv <- naive(x, bw = bw); add("naive", c(bw, length(x), x, 0), length(nv)); add("naive", c(bw, length(x), x, 1), nv[1])
}
# vieu (gaussian): ("vieu") args (bw or 0 for nrd0, n, x...)
for (rep in 1:25) {
  n <- sample(15:100, 1); x <- round(if (rep %% 3 == 0) c(rnorm(n %/% 2, 0, 1), rnorm(n - n %/% 2, 4, 1.3)) else rgamma(n, 3, 1), 3); bw <- if (rep %% 2 == 0) 0 else runif(1, 0.3, 1)
  v <- tryCatch(if (bw == 0) vieu(x) else vieu(x, bw = bw), error = function(e) NULL); if (is.null(v)) next
  cases[[length(cases) + 1]] <- case("vieu", c(bw, length(x), x), v, rel = 1e-9, abs = 1e-9)
}
emit("parzen", "modeest", list(cases))
