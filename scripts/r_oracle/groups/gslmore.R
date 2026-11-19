# gsl: the exported functions the other gsl groups do not reach (Bessel integer and scaled forms, spherical Bessel, arrays, Legendre arrays and derivatives, helpers).
#   "m" (code, a, b, c, d): code per the Neper fixture's dispatch
#   "arr" (kind, idx, p1, p2, x): element idx of an array function (kind: 0 Jn_array p1=nmin, 1 In_array, 2 In_scaled_array, 3 Kn_array, 4 Kn_scaled_array, 5 jl_array p1=lmax, 6 jl_steed_array, 7 yl_array,
#                                 8 il_scaled_array, 9 kl_scaled_array, 10 Yn_array p1=nmin, 11 gegenpoly_array p1=nmax p2=lambda, 12 sequence_Jnu p1=nu)
#   "leg" (kind, norm, csphase, lmax, x, l, m): legendre arrays (kind 0 P, 1 dP/dx, 2 dP/dtheta, 3 d2P/dx2, 4 d2P/dtheta2)
suppressMessages(library(gsl))
cases <- list()
add <- function(fn, args, want, rel = 1e-11, abs = 1e-300) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = abs)
set.seed(20262912)
for (i in 1:25) {
  n <- sample(0:9, 1); x <- runif(1, 0.2, 40); nu <- runif(1, 0, 6); xs <- runif(1, 0.2, 25)
  add("m", c(0, n, min(x, 30)), bessel_In(n, min(x, 30))); add("m", c(1, n, x), bessel_In_scaled(n, x)); add("m", c(2, n, min(x, 30)), bessel_Kn(n, min(x, 30)))
  add("m", c(3, n, x), bessel_Kn_scaled(n, x)); add("m", c(4, nu, x), bessel_Knu_scaled(nu, x)); add("m", c(5, nu, x), bessel_Inu_scaled(nu, x))
  add("m", c(6, nu, x), bessel_lnKnu(nu, x)); add("m", c(7, nu, xs), bessel_Jnu(nu, xs), rel = 1e-10, abs = 1e-12)
  add("m", c(8, 0, x), bessel_J0(x), rel = 1e-10, abs = 1e-12); add("m", c(9, 0, x), bessel_J1(x), rel = 1e-10, abs = 1e-12)
  add("m", c(10, 0, xs), bessel_Y0(xs), rel = 1e-10, abs = 1e-12); add("m", c(11, 0, xs), bessel_Y1(xs), rel = 1e-10, abs = 1e-12)
  add("m", c(12, 0, x), bessel_I0_scaled(x)); add("m", c(13, 0, x), bessel_I1_scaled(x)); add("m", c(14, 0, x), bessel_K0_scaled(x)); add("m", c(15, 0, x), bessel_K1_scaled(x))
  add("m", c(16, 0, min(x, 30)), bessel_I0(min(x, 30))); add("m", c(17, 0, min(x, 30)), bessel_I1(min(x, 30))); add("m", c(18, 0, min(x, 30)), bessel_K0(min(x, 30))); add("m", c(19, 0, min(x, 30)), bessel_K1(min(x, 30)))
  l <- sample(0:12, 1)
  add("m", c(20, l, x), bessel_jl(l, x), rel = 1e-10, abs = 1e-13); add("m", c(21, l, x), bessel_yl(l, x), rel = 1e-10, abs = 1e-13)
  add("m", c(22, l, x), bessel_il_scaled(l, x)); add("m", c(23, l, x), bessel_kl_scaled(l, x))
  add("m", c(24, 0, x), bessel_j0(x), rel = 1e-10, abs = 1e-13); add("m", c(25, 0, x), bessel_j1(x), rel = 1e-10, abs = 1e-13); add("m", c(26, 0, x), bessel_j2(x), rel = 1e-10, abs = 1e-13)
  add("m", c(27, 0, x), bessel_y0(x), rel = 1e-10, abs = 1e-13); add("m", c(28, 0, x), bessel_y1(x), rel = 1e-10, abs = 1e-13); add("m", c(29, 0, x), bessel_y2(x), rel = 1e-10, abs = 1e-13)
  add("m", c(30, 0, x), bessel_i0_scaled(x)); add("m", c(31, 0, x), bessel_i1_scaled(x)); add("m", c(32, 0, x), bessel_i2_scaled(x))
  add("m", c(33, 0, x), bessel_k0_scaled(x)); add("m", c(34, 0, x), bessel_k1_scaled(x)); add("m", c(35, 0, x), bessel_k2_scaled(x))
}
for (i in 1:8) {
  nmin <- sample(0:3, 1); nmax <- nmin + sample(2:6, 1); x <- runif(1, 0.5, 20); lmax <- sample(2:14, 1); lam <- runif(1, 0.3, 3); xx <- runif(1, -1, 1)
  r <- list(bessel_Jn_array(nmin, nmax, x), bessel_In_array(nmin, nmax, min(x, 25)), bessel_In_scaled_array(nmin, nmax, x), bessel_Kn_array(nmin, nmax, min(x, 25)), bessel_Kn_scaled_array(nmin, nmax, x),
            bessel_jl_array(lmax, x), bessel_jl_steed_array(lmax, x), bessel_yl_array(lmax, x), bessel_il_scaled_array(lmax, x), bessel_kl_scaled_array(lmax, x), bessel_Yn_array(nmin, nmax, x))
  for (k in 0:10) {
    v <- as.vector(r[[k + 1]]); p1 <- if (k %in% 5:9) lmax else nmin
    xa <- if (k %in% c(1, 3)) min(x, 25) else x
    tol <- if (k %in% c(0, 5, 6, 7, 10)) 1e-10 else 1e-11
    for (j in seq_along(v)) add("arr", c(k, j - 1, p1, nmax, xa), v[j], rel = tol, abs = 1e-12)
  }
  v <- as.vector(gegenpoly_array(nmax, lam, xx)); for (j in seq_along(v)) add("arr", c(11, j - 1, nmax, lam, xx), v[j])
  vv <- sort(runif(3, 0.5, 15)); s <- as.vector(bessel_sequence_Jnu(0.5 + i * 0.37, vv)); for (j in 1:3) add("arr", c(12, j - 1, 0.5 + i * 0.37, 0, vv[j]), s[j], rel = 1e-10, abs = 1e-12)
}
for (norm in 1:4) for (cs in c(-1, 1)) for (rep in 1:2) {
  lmax <- sample(2:9, 1); x <- runif(1, -0.95, 0.95)
  mats <- list(legendre_array(x, lmax, norm, cs), legendre_deriv_array(x, lmax, norm, cs), legendre_deriv_alt_array(x, lmax, norm, cs), legendre_deriv2_array(x, lmax, norm, cs), legendre_deriv2_alt_array(x, lmax, norm, cs))
  for (kind in 0:4) for (l in 0:lmax) for (m in 0:l) if (l %% 3 == lmax %% 3 || l == lmax) add("leg", c(kind, norm, cs, lmax, x, l, m), mats[[kind + 1]][l + 1, m + 1], rel = 1e-10, abs = 1e-12)
}
emit("gslmore", "gsl", list(cases))
