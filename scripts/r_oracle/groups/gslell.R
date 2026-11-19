# gsl: the elliptic integrals with gsl's error estimates in the three precision modes.
#   "l" (code, part, mode, a, b, c, d): part 0 value, 1 error; code 0 RC(a, b), 1 RD(a, b, c), 2 RF(a, b, c), 3 RJ(a, b, c, d), 4 F(phi = a, k = b), 5 E(a, b), 6 P(a, b, n = c), 7 D(a, b), 8 Kcomp(a), 9 Ecomp(a)
suppressMessages(library(gsl))
cases <- list()
set.seed(20262915)
g <- function(f, ..., mode) f(..., mode = mode, give = TRUE, strict = FALSE)
add2 <- function(code, mode, args, r) {
  cases[[length(cases) + 1]] <<- case("l", c(code, 0, mode, args), r$val, rel = 1e-11, abs = 1e-300)
  cases[[length(cases) + 1]] <<- case("l", c(code, 1, mode, args), r$err, rel = 1e-9, abs = 1e-300)
}
for (i in 1:20) for (mode in 0:2) {
  r <- runif(4, 0.05, 6); k <- runif(1, 0.05, 0.97); ph <- c(runif(1, -1.5, 1.5), runif(1, 1.6, 9), runif(1, -9, -1.6))[sample(1:3, 1)]; nn <- runif(1, -0.6, 2)
  add2(0, mode, r[1:2], g(ellint_RC, r[1], r[2], mode = mode)); add2(1, mode, r[1:3], g(ellint_RD, r[1], r[2], r[3], mode = mode))
  add2(2, mode, r[1:3], g(ellint_RF, r[1], r[2], r[3], mode = mode)); add2(3, mode, r, g(ellint_RJ, r[1], r[2], r[3], r[4], mode = mode))
  add2(4, mode, c(ph, k), g(ellint_F, ph, k, mode = mode)); add2(5, mode, c(ph, k), g(ellint_E, ph, k, mode = mode))
  add2(6, mode, c(ph, k, nn), g(ellint_P, ph, k, nn, mode = mode)); add2(7, mode, c(ph, k), g(ellint_D, ph, k, mode = mode))
  add2(8, mode, k, g(ellint_Kcomp, k, mode = mode)); add2(9, mode, k, g(ellint_Ecomp, k, mode = mode))
}
for (k in c(0.99999999995, 0.999999999, -0.99999999999, 0.9999, 0)) { add2(8, 0, k, g(ellint_Kcomp, k, mode = 0)); add2(9, 0, k, g(ellint_Ecomp, k, mode = 0)) }
for (ph in c(pi / 2, -pi / 2, 3 * pi / 2, pi, 0)) add2(5, 0, c(ph, 0.6), g(ellint_E, ph, 0.6, mode = 0))
emit("gslell", "gsl", list(cases))
