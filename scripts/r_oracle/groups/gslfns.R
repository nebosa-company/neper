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
for (rep in 1:30) {
  ax <- runif(1, 0.05, 5); sg <- sample(c(-1, 1), 1); a <- sg * ax; add("airy_ai", c(a, 0), airy_Ai(a)); add("airy_bi", c(a, 0), airy_Bi(a))
  k <- runif(1, 0, 0.98); ph <- runif(1, 0.05, 1.5); add("kcomp", c(k, 0), ellint_Kcomp(k)); add("ecomp", c(k, 0), ellint_Ecomp(k)); add("ellf", c(ph, k), ellint_F(ph, k)); add("elle", c(ph, k), ellint_E(ph, k))
  r <- runif(3, 0.05, 6); add("rf", r, ellint_RF(r[1], r[2], r[3])); add("rd", r, ellint_RD(r[1], r[2], r[3]))
}
for (rep in 1:30) {
  a <- runif(1, 0.2, 3); b <- runif(1, 0.5, 4); cc <- runif(1, 0.5, 4); x <- runif(1, -0.9, 0.9)
  add("f01", c(b, x * 3), hyperg_0F1(b, x * 3)); add("f11", c(a, b, x * 4), hyperg_1F1(a, b, x * 4)); add("f21", c(a, b, cc, x), hyperg_2F1(a, b, cc, x))
  l <- sample(0:12, 1); m <- sample(0:l, 1); y <- runif(1, -0.99, 0.99); add("pl", c(l, y), legendre_Pl(l, y)); add("plm", c(l, m, y), legendre_Plm(l, m, y))
  f <- runif(1, -10, 20); add("fd0", c(f, 0), fermi_dirac_0(f)); d <- runif(1, -8, 1); add("dilog", c(d, 0), dilog(d)); p <- runif(1, 0.05, 30); add("psi", c(p, 0), psi(p))
}
emit("gslfns", "gsl", list(cases))
