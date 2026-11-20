# gsl: legendre_Ql (every l) and legendre_sphPlm with error estimates.
#   "q" (code, part, l, m, x): part 0 value, 1 error; code 0 legendre_Ql(l, x), 1 legendre_sphPlm(l, m, x)
suppressMessages(library(gsl))
cases <- list()
set.seed(20262958)
add <- function(code, l, m, x, r, vrel = 1e-10, erel = 1e-8) {
  if (is.null(r) || r$status != 0 || !is.finite(r$val)) return()
  cases[[length(cases) + 1]] <<- case("q", c(code, 0, l, m, x), r$val, rel = vrel, abs = 1e-300)
  cases[[length(cases) + 1]] <<- case("q", c(code, 1, l, m, x), r$err, rel = erel, abs = 1e-300)
}
g <- function(f, ...) tryCatch(f(..., give = TRUE, strict = FALSE), error = function(e) NULL)
for (i in 1:150) {
  l <- c(sample(2:40, 1), sample(41:300, 1), sample(1000:5000, 1))[sample(1:3, 1)]
  x <- c(runif(1, -0.99, 0.99), runif(1, 1.001, 3), runif(1, 3, 100))[sample(1:3, 1)]
  add(0, l, 0, x, g(legendre_Ql, l, x), vrel = 1e-9)
  ls <- sample(1:60, 1); m <- sample(0:ls, 1); xs <- runif(1, -0.999, 0.999)
  add(1, ls, m, xs, g(legendre_sphPlm, ls, m, xs), vrel = 1e-9)
}
for (l in c(100001, 250000)) for (x in c(0.3, 1.5, 20)) add(0, l, 0, x, g(legendre_Ql, l, x), vrel = 1e-9)
emit("gslleg", "gsl", list(cases))
