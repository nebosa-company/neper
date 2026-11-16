# randtoolbox: halton, unscrambled sobol and torus points.
#   args: (kind, n, dim)   fn "sum": the sum of value * (row * dim + col + 1) over the n by dim matrix; kind 0 halton 1 sobol 2 torus
suppressMessages(library(randtoolbox))
cases <- list()
add <- function(args, want) cases[[length(cases) + 1]] <<- case("sum", args, want, rel = 1e-10, abs = 1e-9)
w <- function(m) sum(as.vector(t(m)) * seq_len(length(m)))
for (n in c(5, 17, 64, 100)) for (d in 1:8) {
  add(c(0, n, d), w(matrix(halton(n, d), n, d)))
  add(c(1, n, d), w(matrix(sobol(n, d), n, d)))
  add(c(2, n, d), w(matrix(torus(n, d), n, d)))
}
emit("randtoolbox", "randtoolbox", list(cases))
