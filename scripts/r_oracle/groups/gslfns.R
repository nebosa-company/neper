# gslfns: gsl's Bessel K and I of real order, Bessel J of integer order, Lambert W0 and W-1, Hurwitz and Riemann zeta.
#   args: (a, b) = the two arguments in the function's order (zeta uses a only)
suppressMessages(library(gsl))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-14)
set.seed(20262004)
for (rep in 1:40) {
  nu <- runif(1, 0, 5); x <- runif(1, 0.05, 25)
  add("knu", c(nu, x), bessel_Knu(nu, x)); add("inu", c(nu, min(x, 20)), bessel_Inu(nu, min(x, 20)))
  n <- sample(0:8, 1); xj <- runif(1, 0.1, 30); add("jn", c(n, xj), bessel_Jn(n, xj))
  w <- runif(1, -0.36, 10); add("w0", c(w, 0), lambert_W0(w)); wm <- -runif(1, 0.01, 0.36); add("wm1", c(wm, 0), lambert_Wm1(wm))
  s <- runif(1, 1.2, 12); q <- runif(1, 0.1, 6); add("hzeta", c(s, q), hzeta(s, q)); add("zeta", c(s, 1), zeta(s))
}
for (rep in 1:30) {
  x <- runif(1, 0.05, 30); add("e1", c(x, 0), expint_E1(x)); add("ei", c(x, 0), expint_Ei(x)); add("ei", c(-x, 0), expint_Ei(-x))
  d <- runif(1, -8, 8); add("dawson", c(d, 0), dawson(d)); cl <- runif(1, 0.05, 1.5); add("clausen", c(cl, 0), clausen(cl))
}
emit("gslfns", "gsl", list(cases))
