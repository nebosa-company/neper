# gsl: Bessel J0, J1, Y0, Y1 and Jn with error estimates (x >= 1, n <= 50; the Jn Taylor and Olver branches are checked in gslnu.R).
#   "j" (code, part, x, n): part 0 value, 1 error; code 0 J0, 1 J1, 2 Y0, 3 Y1, 4 Jn(n, x)
suppressMessages(library(gsl))
cases <- list()
set.seed(20262922)
add <- function(code, x, n, r) {
  cases[[length(cases) + 1]] <<- case("j", c(code, 0, x, n), r$val, rel = 1e-11, abs = 1e-300)
  cases[[length(cases) + 1]] <<- case("j", c(code, 1, x, n), r$err, rel = 1e-8, abs = 1e-300)
}
g <- function(f, ...) f(..., give = TRUE, strict = FALSE)
for (i in 1:80) {
  x <- c(runif(1, 0, 4), runif(1, 4, 30), runif(1, 30, 1500), 10^runif(1, -9, -3), 10^runif(1, 4, 7))[sample(1:5, 1)]
  sgn <- sample(c(1, -1), 1)
  add(0, sgn * x, 0, g(bessel_J0, sgn * x)); add(1, sgn * x, 0, g(bessel_J1, sgn * x)); add(2, x, 0, g(bessel_Y0, x)); add(3, x, 0, g(bessel_Y1, x))
  xj <- runif(1, 1, 60); if (sample(1:5, 1) == 1) xj <- runif(1, 1000, 3000); n <- sample(c(-5:-2, 2:50), 1)
  add(4, sgn * xj, n, g(bessel_Jn, n, sgn * xj))
}
emit("gslbj", "gsl", list(cases))
