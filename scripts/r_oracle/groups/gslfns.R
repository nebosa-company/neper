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
# Debye, transport, Fermi-Dirac and synchrotron functions (args: (n or order, x)); the quadrature-based ones at 1e-9
for (rep in 1:20) {
  x <- runif(1, 0.1, 12)
  add("debye", c(1, x), debye_1(x)); add("debye", c(2, x), debye_2(x)); add("debye", c(3, x), debye_3(x)); add("debye", c(4, x), debye_4(x))
  for (n in 2:5) add("transport", c(n, x), get(paste0("transport_", n))(x))
  xf <- runif(1, -4, 8)
  add("fd", c(-1, xf), fermi_dirac_m1(xf)); add("fd", c(-0.5, xf), fermi_dirac_mhalf(xf)); add("fd", c(0.5, xf), fermi_dirac_half(xf))
  add("fd", c(1, xf), fermi_dirac_1(xf)); add("fd", c(1.5, xf), fermi_dirac_3half(xf)); add("fd", c(2, xf), fermi_dirac_2(xf))
  xs <- runif(1, 0.05, 8); add("sync", c(1, xs), synchrotron_1(xs)); add("sync", c(2, xs), synchrotron_2(xs))
}
# gamma-family helpers: args (a, b, x) under "h" with the function carried in a leading code: 0 gamma_inc, 1 gamma_inc_P, 2 gamma_inc_Q, 3 beta_inc, 4 poch, 5 lnpoch, 6 pochrel,
# 7 erf, 8 erfc, 9 log_erfc, 10 sinc, 11 lnchoose, 12 lnbeta, 13 lnfact, 14 doublefact, 15 lndoublefact, 16 lnsinh, 17 lncosh, 18 taylorcoeff
for (rep in 1:20) {
  a <- runif(1, 0.3, 6); b <- runif(1, 0.3, 6); x <- runif(1, 0.05, 8); u <- runif(1, 0.01, 0.99); n <- sample(2:25, 1)
  add("h", c(0, a, x), gamma_inc(a, x)); add("h", c(1, a, x), gamma_inc_P(a, x)); add("h", c(2, a, x), gamma_inc_Q(a, x))
  add("h", c(3, a, b, u), beta_inc(a, b, u)); add("h", c(4, a, b), poch(a, b)); add("h", c(5, a, b), lnpoch(a, b)); add("h", c(6, a, b), pochrel(a, b))
  xe <- runif(1, -3, 5); add("h", c(7, xe), erf(xe)); add("h", c(8, xe), erfc(xe)); add("h", c(9, x), log_erfc(x)); add("h", c(10, xe), sinc(xe))
  add("h", c(11, n + 10, n), lnchoose(n + 10, n)); add("h", c(12, a, b), lnbeta(a, b)); add("h", c(13, n), lnfact(n)); add("h", c(14, n), doublefact(n)); add("h", c(15, n), lndoublefact(n))
  add("h", c(16, x), lnsinh(x)); add("h", c(17, x), lncosh(x)); add("h", c(18, n, x), taylorcoeff(n, x))
}
emit("gslfns", "gsl", list(cases))
