# gsl: Riemann zeta, zeta - 1, eta and the integer forms with error estimates (s >= 0).
#   "z" (code, part, s): part 0 value, 1 error; code 0 zeta, 1 zetam1, 2 eta, 3 zeta_int, 4 zetam1_int, 5 eta_int
suppressMessages(library(gsl))
cases <- list()
set.seed(20262921)
fl <- list(zeta, zetam1, eta, zeta_int, zetam1_int, eta_int)
add <- function(code, s) {
  r <- tryCatch(fl[[code + 1]](s, give = TRUE, strict = FALSE), error = function(e) NULL)
  if (is.null(r) || r$status != 0) return()
  cases[[length(cases) + 1]] <<- case("z", c(code, 0, s), r$val, rel = 1e-11, abs = 1e-300)
  cases[[length(cases) + 1]] <<- case("z", c(code, 1, s), r$err, rel = 1e-9, abs = 1e-300)
}
for (i in 1:60) {
  s <- c(runif(1, 0, 1), runif(1, 1.0001, 5), runif(1, 5, 15), runif(1, 15, 20), runif(1, 20, 120))[sample(1:5, 1)]
  add(0, s); add(1, s); add(2, s)
}
for (s in c(0, 1.5, 5, 15, 20, 1.0001, 0.9999, 101, 150)) { add(0, s); add(1, s); add(2, s) }
for (n in c(2:30, 50, 99, 100, 101, 120)) { add(3, n); add(4, n) }
for (n in c(0:30, 100, 101, 130)) add(5, n)
emit("gslzeta", "gsl", list(cases))
