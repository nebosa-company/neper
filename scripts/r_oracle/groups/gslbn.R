# gsl: bessel_Yn, bessel_Kn, bessel_Kn_scaled, bessel_In and bessel_In_scaled with error estimates (n <= 50, x below 280, In n < 150; the Olver branches are checked in gslnu.R).
#   "b" (code, part, n, x): part 0 value, 1 error; code 0 Yn, 1 Kn, 2 Kn_scaled, 3 In, 4 In_scaled
suppressMessages(library(gsl))
cases <- list()
set.seed(20262960)
g <- function(f, ...) tryCatch(f(..., give = TRUE, strict = FALSE), error = function(e) NULL)
add <- function(code, n, x, r, vrel = 1e-10, erel = 1e-8) {
  if (is.null(r) || r$status != 0 || !is.finite(r$val) || r$val == 0) return()
  cases[[length(cases) + 1]] <<- case("b", c(code, 0, n, x), r$val, rel = vrel, abs = 1e-300)
  cases[[length(cases) + 1]] <<- case("b", c(code, 1, n, x), r$err, rel = erel, abs = 1e-300)
}
for (i in 1:150) {
  x <- c(runif(1, 1e-3, 1), runif(1, 1, 5), runif(1, 5, 60), runif(1, 60, 280))[sample(1:4, 1)]
  n <- c(2:9, sample(10:50, 1), sample(-6:-2, 1))[sample(1:10, 1)]
  add(0, n, x, g(bessel_Yn, n, x), vrel = 1e-9)
  nk <- c(0:9, sample(10:200, 1))[sample(1:11, 1)]
  xk <- min(x, 100); add(1, nk, xk, g(bessel_Kn, nk, xk)); add(2, nk, x, g(bessel_Kn_scaled, nk, x))
  ni <- c(0:9, sample(10:149, 1), sample(10:149, 1))[sample(1:12, 1)]
  xi <- c(runif(1, 1e-3, 3), runif(1, 3, 60), runif(1, 60, 1000), 10^runif(1, 3, 6.9))[sample(1:4, 1)] * sample(c(1, 1, -1), 1)
  add(4, ni, xi, g(bessel_In_scaled, ni, xi)); xp <- if (abs(xi) > 700) xi / 10^floor(log10(abs(xi)) - 2) else xi; add(3, ni, xp, g(bessel_In, ni, xp))
}
# Yn above 1/sqrt(eps): the asymptotic error scaling (x stays below 2e9: e.math.sin reduces larger arguments with an error that grows with x)
for (i in 1:60) { n <- sample(2:9, 1); xb <- 10^runif(1, 7.85, 9.3); add(0, n, xb, g(bessel_Yn, n, xb), vrel = 1e-9) }
emit("gslbn", "gsl", list(cases))
