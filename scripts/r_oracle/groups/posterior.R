# posterior: rhat, ess_bulk, ess_tail, mcse_mean of an iterations by chains draws matrix.
#   args: (nchain, n, x chain-major[nchain * n])   fn "rhat" "essb" "esst" "mcse"
suppressMessages(library(posterior))
cases <- list()
add <- function(fn, args, want) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-12)
set.seed(20261202)
for (rep in 1:30) {
  nc <- sample(1:5, 1); n <- sample(c(60, 101, 200, 400), 1); phi <- runif(1, -0.3, 0.9)
  x <- sapply(seq_len(nc), function(k) as.vector(arima.sim(list(ar = phi), n)) + (rep %% 3) * 0.5 * k + (if (rep %% 4 == 0) rt(1, 3) else 0))
  if (rep %% 5 == 0) x <- exp(x / 2)
  x <- matrix(x, n, nc); a <- c(nc, n, as.vector(x))
  add("rhat", a, rhat(x)); add("essb", a, ess_bulk(x)); add("esst", a, ess_tail(x)); add("mcse", a, mcse_mean(x))
}
emit("posterior", "posterior", list(cases))
