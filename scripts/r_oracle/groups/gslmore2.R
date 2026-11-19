# gsl: second batch of exported functions: the complex Jacobian functions, scaled Airy functions, hypergeometric helpers, hydrogenic radial functions and small special functions.
#   "n" (code, a, b, c, d): code per the Neper fixture's dispatch
#   "j" (code, part, zr, zi, m): code 0 cd, 1 cn, 2 cs, 3 dc, 4 dn, 5 ds, 6 nc, 7 nd, 8 ns, 9 sc, 10 sd, 11 sn; part 0 Re, 1 Im (zi = 0 passes a real argument)
suppressMessages(library(gsl))
cases <- list()
add <- function(fn, args, want, rel = 1e-11, abs = 1e-300) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20262913)
for (i in 1:25) {
  n <- sample(1:5, 1); l <- sample(0:(n - 1), 1); z <- runif(1, 0.5, 4); r <- runif(1, 0.1, 12)
  add("n", c(0, n, l, z, r), hydrogenicR(n, l, z, r))
  m <- sample(1:4, 1); nn <- m + sample(1:4, 1); x <- runif(1, 0.1, 6)
  add("n", c(1, m, nn, x), hyperg_1F1_int(m, nn, x), rel = 1e-10); add("n", c(2, m, nn, x), hyperg_U_int(m, nn, x), rel = 1e-10)
  a <- runif(1, 0.2, 3); b <- runif(1, 0.2, 3); cc <- runif(1, 0.5, 4); xx <- runif(1, -0.9, 0.9); ai <- runif(1, 0.1, 2)
  add("n", c(3, a, b, cc, xx), hyperg_2F1_renorm(a, b, cc, xx), rel = 1e-10)
  add("n", c(4, a, ai, cc, xx), hyperg_2F1_conj(a, ai, cc, xx), rel = 1e-10); add("n", c(5, a, ai, cc, xx), hyperg_2F1_conj_renorm(a, ai, cc, xx), rel = 1e-10)
  g <- -runif(1, 0.05, 7); if (abs(g - round(g)) < 0.02) g <- g + 0.1; gp <- runif(1, 0.1, 20); ap <- runif(1, 0.3, 6); xp <- runif(1, 0.1, 4)
  add("n", c(6, g), lngamma(g), rel = 1e-10); add("n", c(6, gp), lngamma(gp)); add("n", c(8, g), lngamma_sgn(g, give = TRUE, strict = FALSE)$sgn, abs = 0.5)
  add("n", c(9, ap, xp), lnpoch_sgn(ap, xp, give = TRUE, strict = FALSE)$val, rel = 1e-10); add("n", c(10, ap, xp), lnpoch_sgn(ap, xp, give = TRUE, strict = FALSE)$sgn, abs = 0.5)
  add("n", c(11, g), log_abs(g)); xr <- runif(1, -3, 3); nr <- sample(-6:9, 1); add("n", c(12, xr, nr), pow_int(xr, nr)); nf <- sample(0:40, 1); add("n", c(13, nf), fact(nf))
  add("n", c(14, xr), erf_Z(xr)); add("n", c(15, xr), erf_Q(xr)); add("n", c(16, gp), expint_E2(gp), rel = 1e-10); q1 <- runif(1, -0.95, 0.95); add("n", c(17, q1), legendre_Q1(q1), rel = 1e-10)
  zn <- sample(2:30, 1); add("n", c(18, zn), zetam1_int(zn), rel = 1e-10); py <- runif(1, -15, 15); add("n", c(19, py), psi_1piy(py))
  cf <- runif(4, -2, 2); add("n", c(20, cf, xr), gsl_poly(cf, xr))
  add("n", c(21, ap, xp), gsl_sf_beta(ap, xp)); nc <- sample(0:30, 1); mc <- sample(0:nc, 1); add("n", c(22, nc, mc), gsl_sf_choose(nc, mc))
  add("n", c(23, g), gsl_sf_gamma(g)); add("n", c(24, xr * 5), gsl_sf_cos(xr * 5)); add("n", c(25, xr * 5), gsl_sf_sin(xr * 5)); add("n", c(26, gp), gsl_sf_log(gp))
  xa <- runif(1, -6, 8)
  add("n", c(27, 0, xa), airy_Ai_scaled(xa), rel = 1e-10); add("n", c(27, 1, xa), airy_Bi_scaled(xa), rel = 1e-10)
  add("n", c(27, 2, xa), airy_Ai_deriv_scaled(xa), rel = 1e-10); add("n", c(27, 3, xa), airy_Bi_deriv_scaled(xa), rel = 1e-10)
  lam <- runif(1, 0.3, 4); eta <- runif(1, 0.4, 3); l3 <- sample(0:8, 1)
  add("n", c(28, lam, eta), legendre_H3d_0(lam, eta), rel = 1e-10); add("n", c(29, lam, eta), legendre_H3d_1(lam, eta), rel = 1e-10)
  h <- as.vector(legendre_H3d_array(8, lam, eta)); add("n", c(30, l3, lam, eta), h[l3 + 1], rel = 1e-10)
  xl <- runif(1, -1, 1); p <- as.vector(legendre_Pl_array(9, xl)); add("n", c(31, l3, xl), p[l3 + 1], rel = 1e-10)
}
for (k in c(2, 5, 9)) { add("n", c(32, k), legendre_array_n(k), abs = 0.5); for (m in 0:min(k, 2)) add("n", c(33, k, m), legendre_array_index(k, m), abs = 0.5) }
for (rep in 1:30) {
  u <- runif(1, -2, 2); v <- runif(1, 0.1, 1.5); m <- runif(1, 0.05, 0.9); fl <- list(gsl_cd, gsl_cn, gsl_cs, gsl_dc, gsl_dn, gsl_ds, gsl_nc, gsl_nd, gsl_ns, gsl_sc, gsl_sd, gsl_sn)
  for (code in 0:11) {
    z <- complex(real = u, imaginary = v); w <- fl[[code + 1]](z, m)
    add("j", c(code, 0, u, v, m), Re(w), rel = 1e-9, abs = 1e-12); add("j", c(code, 1, u, v, m), Im(w), rel = 1e-9, abs = 1e-12)
    add("j", c(code, 0, u, 0, m), fl[[code + 1]](u, m), rel = 1e-9, abs = 1e-12)
  }
}
emit("gslmore2", "gsl", list(cases))
