# gsl: psi, psi_int, psi_1, psi_1_int and psi_n with error estimates.
#   "p" (code, part, x, n): part 0 value, 1 error; code 0 psi(x), 1 psi_int(n), 2 psi_1(x), 3 psi_1_int(n), 4 psi_n(n, x)
suppressMessages(library(gsl))
cases <- list()
set.seed(20262924)
add <- function(code, x, n, r) {
  if (is.null(r) || r$status != 0 || !is.finite(r$val)) return()
  cases[[length(cases) + 1]] <<- case("p", c(code, 0, x, n), r$val, rel = 1e-10, abs = 1e-13)
  cases[[length(cases) + 1]] <<- case("p", c(code, 1, x, n), r$err, rel = 1e-8, abs = 1e-300)
}
g <- function(f, ...) tryCatch(f(..., give = TRUE, strict = FALSE), error = function(e) NULL)
for (i in 1:100) {
  x <- c(runif(1, 0.01, 1), runif(1, 1, 2), runif(1, 2, 40), runif(1, -1, 0), runif(1, -2, -1), runif(1, -30, -2), 10^runif(1, 2, 6))[sample(1:7, 1)]
  if (abs(x - round(x)) > 0.02 || x > 0) { add(0, x, 0, g(psi, x)); add(2, x, 0, g(psi_1, x)) }
  xp <- runif(1, 0.05, 30); n <- sample(2:8, 1); add(4, xp, n, g(psi_n, n, xp))
  ni <- sample(c(1:120, 150, 1000), 1); add(1, 0, ni, g(psi_int, ni)); add(3, 0, ni, g(psi_1_int, ni))
}
emit("gslpsi", "gsl", list(cases))
