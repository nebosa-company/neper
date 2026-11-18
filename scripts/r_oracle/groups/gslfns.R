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
# polygamma and helpers under "h2": 0 psi_1, 1 psi_n, 2 gammainv, 3 gammastar, 4 hypot (args (code, a, b))
for (rep in 1:20) {
  x <- runif(1, 0.3, 9); n <- sample(1:5, 1); y <- runif(1, 0.3, 9)
  cases[[length(cases) + 1]] <- case("h2", c(0, x, 0), psi_1(x), rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("h2", c(1, n, x), psi_n(n, x), rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("h2", c(2, x, 0), gammainv(x), rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("h2", c(3, x, 0), gammastar(x), rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("h2", c(4, x, y), hypot(x, y), rel = 1e-12, abs = 1e-14)
}
# integrals, polynomials and elliptic functions under "h3": 0 Si, 1 Ci, 2 Shi, 3 Chi, 4 atanint, 5 expint_3, 6 expint_En (n, x), 7 eta, 8 zetam1, 9 laguerre_n (n, a, x),
# 10 gegenpoly_n, 11 legendre_Q0, 12 legendre_Ql (l, x), 13 log_1plusx, 14 log_1plusx_mx, 15 ellint_RC, 16 sn, 17 cn, 18 dn (u, m)
for (rep in 1:15) {
  x <- runif(1, 0.1, 9); n <- sample(1:6, 1); u <- runif(1, -3, 3); m <- runif(1, 0.01, 0.99); q <- runif(1, -0.9, 0.9); y <- runif(1, 0.2, 5); s <- runif(1, 1.5, 8)
  add("h3", c(0, x), Si(x)); add("h3", c(1, x), Ci(x)); add("h3", c(2, x), Shi(x)); add("h3", c(3, x), Chi(x)); add("h3", c(4, x), atanint(x)); add("h3", c(5, x), expint_3(x))
  add("h3", c(6, n, x), expint_En(n, x)); add("h3", c(7, s), eta(s)); add("h3", c(8, s), zetam1(s))
  add("h3", c(9, n, y, x), laguerre_n(n, y, x)); add("h3", c(10, n, y, q), gegenpoly_n(n, y, q)); add("h3", c(11, q), legendre_Q0(q)); add("h3", c(12, n, q), legendre_Ql(n, q))
  add("h3", c(13, q), log_1plusx(q)); add("h3", c(14, q), log_1plusx_mx(q)); add("h3", c(15, x, y), ellint_RC(x, y))
  jj <- elljac(u, m); add("h3", c(16, u, m), jj$sn); add("h3", c(17, u, m), jj$cn); add("h3", c(18, u, m), jj$dn)
}
# ellint_RJ, ellint_P, ellint_D and the Bessel Y functions under "h4": 0 RJ (x, y, z, p), 1 P (phi, k, n), 2 D (phi, k), 3 Yn (n, x)
for (rep in 1:15) {
  r <- runif(4, 0.1, 5); ph <- runif(1, 0.1, 1.4); k <- runif(1, 0.05, 0.9); nn <- runif(1, -0.5, 2); n <- sample(0:4, 1); x <- runif(1, 0.3, 15)
  cases[[length(cases) + 1]] <- case("h4", c(0, r), ellint_RJ(r[1], r[2], r[3], r[4]), rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("h4", c(1, ph, k, nn), ellint_P(ph, k, nn), rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("h4", c(2, ph, k), ellint_D(ph, k), rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("h4", c(3, n, x), bessel_Yn(n, x), rel = 1e-9, abs = 1e-12)
}
for (rep in 1:20) {
  nu <- runif(1, 0.1, 4.9); if (abs(nu - round(nu)) < 0.05) nu <- nu + 0.2; x <- runif(1, 0.4, 12)
  cases[[length(cases) + 1]] <- case("h5", c(nu, x), bessel_Ynu(nu, x), rel = 1e-8, abs = 1e-11)
}
# low-order polynomials and helpers under "h6": 0 laguerre_k (k in arg 2, a, x), 1 gegenpoly_k, 2 legendre_Pk (k, x), 3 sphPlm (l, m, x), 4 hyperg_U, 5 hyperg_2F0, 6 zeta_int,
# 7 eta_int, 8 psi_int, 9 psi_1_int, 10 fermi_dirac_inc_0, 11 fermi_dirac_int, 12 hydrogenicR_1
for (rep in 1:15) {
  a <- runif(1, 0.2, 3); x <- runif(1, 0.1, 3); q <- runif(1, -0.9, 0.9); k <- sample(1:3, 1); n <- sample(2:8, 1); b <- runif(1, 0.3, 4); l <- sample(0:5, 1); m <- sample(0:l, 1)
  fn_l <- c(laguerre_1, laguerre_2, laguerre_3)[[k]]; fn_g <- c(gegenpoly_1, gegenpoly_2, gegenpoly_3)[[k]]; fn_p <- c(legendre_P1, legendre_P2, legendre_P3)[[k]]
  add("h6", c(0, k, a, x), fn_l(a, x)); add("h6", c(1, k, a, q), fn_g(a, q)); add("h6", c(2, k, q), fn_p(q)); add("h6", c(3, l, m, q), legendre_sphPlm(l, m, q))
  add("h6", c(4, a, b, x), hyperg_U(a, b, x)); add("h6", c(5, a, b, -x), hyperg_2F0(a, b, -x)); add("h6", c(6, n), zeta_int(n)); add("h6", c(7, n), eta_int(n))
  add("h6", c(8, n), psi_int(n)); add("h6", c(9, n), psi_1_int(n)); add("h6", c(10, a, b), fermi_dirac_inc_0(a, b)); add("h6", c(11, k, x), fermi_dirac_int(k, x))
  add("h6", c(12, a, x), hydrogenicR_1(a, x))
}
# coupling coefficients (twice the angular momenta): 3j under "c3" (6 args), 6j under "c6" (6 args), 9j under "c9" (9 args)
set.seed(20262601)
n3 <- 0
while (n3 < 40) {
  j <- sample(0:8, 3, TRUE); if (sum(j) %% 2 != 0 || j[1] + j[2] < j[3] || j[1] + j[3] < j[2] || j[2] + j[3] < j[1]) next
  m1 <- sample(seq(-j[1], j[1], by = 2), 1); m2 <- sample(seq(-j[2], j[2], by = 2), 1); m3 <- -m1 - m2
  if (abs(m3) > j[3] || (j[3] + m3) %% 2 != 0) next
  cases[[length(cases) + 1]] <- case("c3", c(j, m1, m2, m3), coupling_3j(j[1], j[2], j[3], m1, m2, m3), rel = 1e-9, abs = 1e-12); n3 <- n3 + 1
}
n6 <- 0
while (n6 < 40) {
  j <- sample(0:6, 6, TRUE)
  ok <- function(a, b, c) (a + b + c) %% 2 == 0 && a + b >= c && a + c >= b && b + c >= a
  if (!(ok(j[1], j[2], j[3]) && ok(j[1], j[5], j[6]) && ok(j[4], j[2], j[6]) && ok(j[4], j[5], j[3]))) next
  cases[[length(cases) + 1]] <- case("c6", j, coupling_6j(j[1], j[2], j[3], j[4], j[5], j[6]), rel = 1e-9, abs = 1e-12); n6 <- n6 + 1
}
n9 <- 0
while (n9 < 15) {
  j <- sample(0:4, 9, TRUE)
  ok <- function(a, b, c) (a + b + c) %% 2 == 0 && a + b >= c && a + c >= b && b + c >= a
  if (!(ok(j[1], j[2], j[3]) && ok(j[4], j[5], j[6]) && ok(j[7], j[8], j[9]) && ok(j[1], j[4], j[7]) && ok(j[2], j[5], j[8]) && ok(j[3], j[6], j[9]))) next
  cases[[length(cases) + 1]] <- case("c9", j, coupling_9j(j[1], j[2], j[3], j[4], j[5], j[6], j[7], j[8], j[9]), rel = 1e-8, abs = 1e-11); n9 <- n9 + 1
}
# conical functions under "k1" (0 half, 1 mhalf; lambda, x) and complex functions under "k2" (0 log, 1 sin, 2 cos, 3 logsin; part 0 re / 1 im; re, im)
for (rep in 1:20) {
  lam <- runif(1, 0.2, 3); x <- c(runif(1, -0.8, 0.95), runif(1, 1.1, 5))[sample(1:2, 1)]
  cases[[length(cases) + 1]] <- case("k1", c(0, lam, x), conicalP_half(lam, x), rel = 1e-10, abs = 1e-13)
  cases[[length(cases) + 1]] <- case("k1", c(1, lam, x), conicalP_mhalf(lam, x), rel = 1e-10, abs = 1e-13)
  z <- complex(real = runif(1, -3, 3), imaginary = runif(1, -2, 2))
  fl <- list(complex_log(z), complex_sin(z), complex_cos(z), complex_logsin(z))
  for (k in 0:3) for (pt in 0:1) cases[[length(cases) + 1]] <- case("k2", c(k, pt, Re(z), Im(z)), if (pt == 0) Re(fl[[k + 1]]) else Im(fl[[k + 1]]), rel = 1e-10, abs = 1e-13)
}
emit("gslfns", "gsl", list(cases))
