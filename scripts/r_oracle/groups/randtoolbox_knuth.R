# randtoolbox::knuthTAOCP after setSeed(seed).
#   args: (seed, n, d)
#   fn "knuth": the sum of value * (row * d + col + 1) over the n by d matrix, row by row, accumulated in a
#   double loop
suppressMessages(library(randtoolbox))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("knuth", args, want, rel = 0, abs = 0)
w <- function(m) {
  v <- as.vector(t(m))
  s <- 0
  for (i in seq_along(v)) s <- s + v[i] * i
  s
}
set.seed(20270102)
for (rep in 1:20) {
  n <- sample(c(5, 17, 60, 100, 101, 150), 1); d <- sample(1:4, 1); sd <- sample(1:1000000, 1)
  setSeed(sd)
  add(c(sd, n, d), w(matrix(knuthTAOCP(n, d), n, d)))
}
emit("randtoolbox_knuth", "randtoolbox", list(cases))
