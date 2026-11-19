# gsl: value and error estimate (give = TRUE, strict = FALSE) of hypot, sinc, lnsinh, lncosh, log_1plusx, taylorcoeff, doublefact, lnfact, lndoublefact, lnchoose, gammastar, gsl_sf_gamma, lnbeta.
# R's lnchoose wrapper calls gsl_sf_choose_e, so code 9 is checked against that behaviour.
#   "e" (code, part, a, b): part 0 value, 1 error; code 0 hypot(a,b), 1 sinc, 2 lnsinh, 3 lncosh, 4 log_1plusx, 5 taylorcoeff(a=n,b=x), 6 doublefact, 7 lnfact, 8 lndoublefact, 9 lnchoose(a,b),
#   10 gammastar, 11 gamma, 12 lnbeta(a,b), 13 log_1plusx_mx
suppressMessages(library(gsl))
cases <- list()
set.seed(20262951)
g <- function(f, ...) f(..., give = TRUE, strict = FALSE)
add2 <- function(code, a, b, r, vrel = 1e-11, erel = 1e-9) {
  if (r$status != 0 || !is.finite(r$val)) return()
  cases[[length(cases) + 1]] <<- case("e", c(code, 0, a, b), r$val, rel = vrel, abs = 1e-300)
  cases[[length(cases) + 1]] <<- case("e", c(code, 1, a, b), r$err, rel = erel, abs = 1e-300)
}
for (i in 1:40) {
  x <- c(runif(1, -3, 3), runif(1, -1e-5, 1e-5), runif(1, -50, 50), runif(1, -1e4, 1e4), runif(1, 90, 110))[sample(1:5, 1)]
  y <- runif(1, -30, 30)
  add2(0, x, y, g(hypot, x, y)); add2(1, x, 0, g(sinc, x))
  px <- c(runif(1, 1e-4, 0.9), runif(1, 1, 30), runif(1, 30, 400))[sample(1:3, 1)]
  add2(2, px, 0, g(lnsinh, px)); add2(3, x, 0, g(lncosh, x))
  lx <- c(runif(1, -0.9, -0.5), runif(1, -0.5, 0.5), runif(1, -1e-3, 1e-3), runif(1, 0.5, 20))[sample(1:4, 1)]
  add2(4, lx, 0, g(log_1plusx, lx)); add2(13, lx, 0, g(log_1plusx_mx, lx))
  n <- sample(2:30, 1); tx <- runif(1, 0.1, 10); add2(5, n, tx, g(taylorcoeff, n, tx))
  m <- sample(0:290, 1); add2(6, m, 0, g(doublefact, m)); add2(8, m, 0, g(lndoublefact, m))
  nf <- sample(c(0:170, 171:400), 1); add2(7, nf, 0, g(lnfact, nf))
  nn <- sample(c(2:60, 100:300), 1); k <- sample(1:(nn - 1), 1); add2(9, nn, k, g(lnchoose, nn, k))
  gx <- c(runif(1, 0.01, 0.5), runif(1, 0.5, 2), runif(1, 2, 10), runif(1, 10, 100), runif(1, 100, 1e5), 10^runif(1, 8, 17))[sample(1:6, 1)]
  add2(10, gx, 0, g(gammastar, gx))
  gm <- c(runif(1, 0.5, 5), runif(1, 5, 10), runif(1, 10, 170), runif(1, -10, 0.5), sample(1:170, 1), 1 + runif(1, -0.009, 0.009), 2 + runif(1, -0.009, 0.009))[sample(1:7, 1)]
  add2(11, gm, 0, g(gsl_sf_gamma, gm), vrel = 1e-10)
  bx <- c(runif(1, 0.01, 50), runif(1, 0.01, 3))[sample(1:2, 1)]; by <- c(runif(1, 0.01, 50), bx * runif(1, 5, 500))[sample(1:2, 1)]
  add2(12, bx, by, g(lnbeta, bx, by), erel = 1e-8)
}
emit("gslerr2", "gsl", list(cases))
