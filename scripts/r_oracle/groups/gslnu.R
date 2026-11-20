# gsl: Bessel functions of real order (Jnu, Ynu, Inu, Inu_scaled, Knu, Knu_scaled, lnKnu) and the large-order integer Jn, Yn, Kn, Kn_scaled, In, In_scaled (the Olver and Taylor branches), value and error.
#   "u" (code, part, nu, x): part 0 value, 1 error; code 0 Jnu, 1 Ynu, 2 Inu, 3 Inu_scaled, 4 Knu, 5 Knu_scaled, 6 lnKnu, 7 Jn, 8 Yn, 9 Kn, 10 Kn_scaled, 11 In, 12 In_scaled
suppressMessages(library(gsl))
cases <- list()
set.seed(20263110)
g <- function(f, ...) tryCatch(f(..., give = TRUE, strict = FALSE), error = function(e) NULL)
add <- function(code, nu, x, r, vrel = 1e-9, erel = 1e-8) {
  if (is.null(r) || r$status != 0 || !is.finite(r$val) || r$val == 0 || !is.finite(r$err)) return()
  cases[[length(cases) + 1]] <<- case("u", c(code, 0, nu, x), r$val, rel = vrel, abs = 1e-300)
  cases[[length(cases) + 1]] <<- case("u", c(code, 1, nu, x), r$err, rel = erel, abs = 1e-300)
}
for (i in 1:120) {
  nu <- c(runif(1, 0, 1), runif(1, 1, 8), runif(1, 8, 50), runif(1, 50, 120), -runif(1, 0, 6))[sample(1:5, 1)]
  x <- c(runif(1, 1e-2, 1.9), runif(1, 2, 10), runif(1, 10, 80), runif(1, 80, 300), runif(1, 1000, 3000))[sample(1:5, 1)]
  add(0, nu, x, g(bessel_Jnu, nu, x)); add(1, nu, x, g(bessel_Ynu, nu, x))
  nup <- abs(nu); xi <- min(x, 700)
  add(2, nup, xi, g(bessel_Inu, nup, xi)); add(3, nup, x, g(bessel_Inu_scaled, nup, x))
  add(4, nup, xi, g(bessel_Knu, nup, xi)); add(5, nup, x, g(bessel_Knu_scaled, nup, x)); add(6, nup, x, g(bessel_lnKnu, nup, x))
}
for (i in 1:120) {
  n <- c(sample(60:150, 1), sample(150:500, 1))[sample(1:2, 1)]
  x <- c(runif(1, 1, n), runif(1, n, 2 * n), runif(1, 2 * n, 10 * n), runif(1, 1e-3, 1))[sample(1:4, 1)]
  add(7, n, x, g(bessel_Jn, n, x), vrel = 1e-8); add(8, n, x, g(bessel_Yn, n, x), vrel = 1e-8)
  xk <- c(runif(1, 5, 2 * n), runif(1, 2 * n, 20 * n))[sample(1:2, 1)]
  add(9, n, xk, g(bessel_Kn, n, xk)); add(10, n, xk, g(bessel_Kn_scaled, n, xk))
  ni <- sample(150:500, 1); xi <- c(runif(1, 1, ni), runif(1, ni, 4 * ni), runif(1, 4 * ni, 3000))[sample(1:3, 1)] * sample(c(1, 1, -1), 1)
  add(12, ni, xi, g(bessel_In_scaled, ni, xi)); xp <- if (abs(xi) > 700) xi / 10 else xi; add(11, ni, xp, g(bessel_In, ni, xp))
}
for (i in 1:30) {  # Jn Taylor branch: small x, n >= 2
  n <- sample(2:50, 1); x <- 10^runif(1, -3, 0) * sqrt(n + 1)
  add(7, n, x, g(bessel_Jn, n, x), vrel = 1e-10)
}
emit("gslnu", "gsl", list(cases))
