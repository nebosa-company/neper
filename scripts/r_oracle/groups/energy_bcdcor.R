# energy::bcdcor (bias-corrected distance correlation). Args: (n, dx, dy, x[n dx] row-major, y[n dy] row-major, which); which 0 is the value.
suppressMessages(library(energy))
cases <- list()
add <- function(fn, args, want, rel = 1e-9, abs = 1e-12) if (is.finite(want)) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20261238)
flat <- function(m) as.vector(t(unclass(m)))
for (rep in 1:18) {
  n <- sample(8:40, 1); dx <- c(1, 2, 3)[(rep - 1) %% 3 + 1]; dy <- c(1, 2)[(rep - 1) %/% 3 %% 2 + 1]
  x <- matrix(rnorm(n * dx), n, dx)
  y <- if (rep %% 2 == 0) x[, 1]^2 + rnorm(n, sd = 0.3) else matrix(rnorm(n * dy), n, dy)
  y <- matrix(y, n, dy)
  add("bc", c(n, dx, dy, flat(x), flat(y), 0), as.numeric(bcdcor(x, y)))
}
emit("energy_bcdcor", "energy", list(cases))
