# qrng::korobov with randomize = "none". A single generator value is extended by qrng to
# a^(0:(d-1)) %% n, and each column is a running sum of generator[j]/n that wraps once above 1.
#   args: (n, d, l, generator[l]) with l 1 for a single value or d for a vector
#   fn "sum": the sum of value * (row * d + col + 1) over the n by d matrix, row by row
suppressMessages(library(qrng))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("sum", args, want, rel = 0, abs = 0)
w <- function(m) {
  v <- as.vector(t(m))
  s <- 0
  for (i in seq_along(v)) s <- s + v[i] * i
  s
}
set.seed(20270101)
for (rep in 1:25) {
  n <- sample(c(2, 7, 11, 13, 16, 17, 25, 31, 64, 100, 101, 128, 1000), 1)
  d <- sample(1:5, 1)
  if (rep %% 2 == 0 && d > 1) {
    gen <- sample(1:(n - 1), d, replace = TRUE)
    l <- d
  } else {
    gen <- sample(1:(n - 1), 1)
    l <- 1
  }
  m <- matrix(korobov(n, d, generator = gen), n, d)
  add(c(n, d, l, gen), w(m))
}
emit("qrng_korobov", "qrng", list(cases))
