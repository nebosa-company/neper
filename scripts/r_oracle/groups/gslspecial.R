# gsl: Dawson, Clausen and the exponential integrals E1, E2, Ei with error estimates.
#   "s" (code, part, x): part 0 value, 1 error; code 0 dawson, 1 clausen, 2 expint_E1, 3 expint_E2, 4 expint_Ei
suppressMessages(library(gsl))
cases <- list()
set.seed(20262917)
add2 <- function(code, x, r) {
  cases[[length(cases) + 1]] <<- case("s", c(code, 0, x), r$val, rel = 1e-11, abs = 1e-300)
  cases[[length(cases) + 1]] <<- case("s", c(code, 1, x), r$err, rel = 1e-9, abs = 1e-300)
}
g <- function(f, ...) f(..., give = TRUE, strict = FALSE)
for (i in 1:60) {
  d <- c(runif(1, -1, 1), runif(1, -4, 4), runif(1, 4, 60), 10^runif(1, 2, 7) * sample(c(-1, 1), 1), runif(1, -1e-8, 1e-8))[sample(1:5, 1)]
  add2(0, d, g(dawson, d))
  cl <- c(runif(1, 0, pi), runif(1, -20, 20), 10^runif(1, -9, -6), runif(1, 0, 2000))[sample(1:4, 1)]; add2(1, cl, g(clausen, cl))
  x <- c(runif(1, -40, -10), runif(1, -10, -4), runif(1, -4, -1), runif(1, -1, 1), runif(1, 1, 4), runif(1, 4, 50), runif(1, 100, 600))[sample(1:7, 1)]
  if (abs(x) > 1e-9) { add2(2, x, g(expint_E1, x)); add2(4, x, g(expint_Ei, x)) }
  if (abs(x) > 1e-9) add2(3, x, g(expint_E2, x))
}
for (x in c(0, 1e-12, 99.99, 100, 100.01)) add2(3, x, g(expint_E2, x))
emit("gslspecial", "gsl", list(cases))
