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
# congruRand: ("cong") args (seed, mod, mult, incr, n, dim) -> sum of value * position over the n by dim matrix
for (rep in 1:20) {
  md <- sample(c(2^31 - 1, 2^31, 2^32, 1000003, 65537), 1); mu <- sample(c(16807, 48271, 69069, 1103515245, 7), 1); inc <- sample(c(0, 1, 12345), 1); sd <- sample(1:1e5, 1); n <- sample(3:12, 1); dm <- sample(1:4, 1)
  setSeed(sd); v <- tryCatch(congruRand(n, dim = dm, mod = md, mult = mu, incr = inc), error = function(e) NULL); if (is.null(v)) next; cases[[length(cases) + 1]] <- case("cong", c(sd, md, mu, inc, n, dm), sum(as.vector(t(matrix(v, n, dm))) * seq_len(n * dm)), rel = 1e-10, abs = 1e-9)
}
emit("randtoolbox", "randtoolbox", list(cases))
