# gsl: value and error estimate (give = TRUE, strict = FALSE) of the functions whose gsl error terms are closed forms.
#   "e" (code, part, a, b, c): part 0 value, 1 error; code 0 sin, 1 cos, 2 log, 3 log_abs, 4 pow_int(a, b), 5 fact(a), 6 choose(a, b), 7 erf_Z, 8 lngamma, 9 lngamma_sgn (part 2 the sign),
#   10 psi_1piy, 11 P1, 12 P2, 13 P3, 14 Pl(a, b), 15 Plm(a, b, c), 16 laguerre_1(a, b), 17 laguerre_2, 18 laguerre_3, 19 gegenpoly_1, 20 gegenpoly_2, 21 gegenpoly_3, 22 gegenpoly_n(a, b, c), 23 Q0, 24 Q1
suppressMessages(library(gsl))
cases <- list()
set.seed(20262914)
add2 <- function(code, args, r, vrel = 1e-11, erel = 1e-9) {
  cases[[length(cases) + 1]] <<- case("e", c(code, 0, args), r$val, rel = vrel, abs = 1e-300)
  cases[[length(cases) + 1]] <<- case("e", c(code, 1, args), r$err, rel = erel, abs = 1e-300)
}
g <- function(f, ...) f(..., give = TRUE, strict = FALSE)
for (i in 1:30) {
  x <- c(runif(1, -3, 3), runif(1, -1e-4, 1e-4), runif(1, -50, 50), runif(1, -1e5, 1e5))[sample(1:4, 1)]
  add2(0, x, g(gsl_sf_sin, x)); add2(1, x, g(gsl_sf_cos, x))
  px <- runif(1, 0.01, 100); add2(2, px, g(gsl_sf_log, px)); add2(3, -px, g(log_abs, -px))
  b <- sample(-8:12, 1); xb <- runif(1, 0.3, 3); add2(4, c(xb, b), g(pow_int, xb, b))
  n <- sample(0:60, 1); add2(5, n, g(fact, n)); nn <- sample(2:60, 1); m <- sample(1:(nn - 1), 1); add2(6, c(nn, m), g(gsl_sf_choose, nn, m))
  xe <- runif(1, -6, 6); add2(7, xe, g(erf_Z, xe))
  lg <- c(runif(1, 0.5, 30), runif(1, 0.01, 0.5), runif(1, -0.98, -0.02), runif(1, -6.9, -1.1))[sample(1:4, 1)]
  fr <- lg - floor(lg); if (lg < -1.5 && (fr < 0.02 || fr > 0.98)) lg <- lg + 0.3
  add2(8, lg, g(lngamma, lg), erel = 1e-8)
  r <- g(lngamma_sgn, lg); add2(9, lg, r, erel = 1e-8); cases[[length(cases) + 1]] <- case("e", c(9, 2, lg, 0, 0), r$sgn, rel = 0, abs = 0.5)
  yp <- c(runif(1, -1, 1), runif(1, 1.1, 10), runif(1, 11, 900), runif(1, 1001, 5000))[sample(1:4, 1)]; add2(10, yp, g(psi_1piy, yp), vrel = 1e-11, erel = 1e-8)
  xl <- runif(1, -1, 1); add2(11, xl, g(legendre_P1, xl)); add2(12, xl, g(legendre_P2, xl)); add2(13, xl, g(legendre_P3, xl))
  l <- sample(2:30, 1); add2(14, c(l, xl), g(legendre_Pl, l, xl)); lm <- sample(0:12, 1); l2 <- lm + sample(0:10, 1); add2(15, c(l2, lm, xl), g(legendre_Plm, l2, lm, xl), vrel = 1e-10, erel = 1e-8)
  a <- runif(1, -1.5, 4); xx <- runif(1, -3, 6)
  add2(16, c(a, xx), g(laguerre_1, a, xx)); add2(17, c(a, xx), g(laguerre_2, a, xx)); add2(18, c(a, xx), g(laguerre_3, a, xx))
  lam <- runif(1, -0.4, 3); add2(19, c(lam, xl), g(gegenpoly_1, lam, xl)); add2(20, c(lam, xl), g(gegenpoly_2, lam, xl)); add2(21, c(lam, xl), g(gegenpoly_3, lam, xl))
  n4 <- sample(4:20, 1); add2(22, c(n4, lam, xl), g(gegenpoly_n, n4, lam, xl)); add2(22, c(n4, 0, xl), g(gegenpoly_n, n4, 0, xl))
  q <- c(runif(1, -0.99, -0.01), runif(1, 0.01, 0.99), runif(1, 1.01, 30), runif(1, -0.04, 0.04))[sample(1:4, 1)]; add2(23, q, g(legendre_Q0, q)); add2(24, q, g(legendre_Q1, q))
}
for (n in c(16, 17, 18, 19, 25)) add2(5, n, g(fact, n))
for (x in c(-1.007, -0.993, 0.015, -0.015, 1.005, 2.003)) { r <- g(lngamma_sgn, x); add2(8, x, g(lngamma, x), erel = 1e-8); cases[[length(cases) + 1]] <- case("e", c(9, 2, x, 0, 0), r$sgn, rel = 0, abs = 0.5) }
emit("gslerr", "gsl", list(cases))
