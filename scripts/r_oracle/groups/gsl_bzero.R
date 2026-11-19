# gsl: bessel_zero_Jnu(nu, s) and the integer-order bessel_zero_J0 / J1. Args: (nu, s)
suppressMessages(library(gsl))
cases <- list()
set.seed(20262430)
for (rep in 1:60) {
  nu <- c(0, 1, runif(1, 0, 4), runif(1, 0, 8))[rep %% 4 + 1]; s <- sample(1:20, 1); if (nu != floor(nu)) s <- sample(1:2, 1)
  r <- tryCatch(bessel_zero_Jnu(nu, s), error = function(e) NA)
  if (is.finite(r)) cases[[length(cases) + 1]] <- case("zj", c(nu, s), r, rel = 1e-10, abs = 1e-10)
}
# "az" (kind 0 Ai 1 Bi 2 Ai-prime 3 Bi-prime, s): airy_zero_*; "ad" (kind 2 Ai-prime 3 Bi-prime, x): airy_Ai_deriv, airy_Bi_deriv
for (kd in 0:3) for (s in 1:3) {
  r <- tryCatch(c(airy_zero_Ai, airy_zero_Bi, airy_zero_Ai_deriv, airy_zero_Bi_deriv)[[kd + 1]](s), error = function(e) NA)
  if (is.finite(r)) cases[[length(cases) + 1]] <- case("az", c(kd, s), r, rel = 1e-9, abs = 1e-10)
}
for (rep in 1:30) {
  x <- runif(1, -4, 3)
  cases[[length(cases) + 1]] <- case("ad", c(2, x), airy_Ai_deriv(x), rel = 1e-9, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("ad", c(3, x), airy_Bi_deriv(x), rel = 1e-9, abs = 1e-12)
}
# "h3" (l, lambda, eta): legendre_H3d
for (rep in 1:50) {
  l <- sample(0:6, 1); lam <- runif(1, 0.3, 4); eta <- runif(1, 0.4, 3)
  cases[[length(cases) + 1]] <- case("h3", c(l, lam, eta), legendre_H3d(l, lam, eta), rel = 1e-9, abs = 1e-12)
}
for (x in c(-8, -3, -1, 0, 0.5, 2, 5, 10, 30, 100, runif(20, -6, 40))) cases[[length(cases) + 1]] <- case("hz", c(x), hazard(x), rel = 1e-12, abs = 1e-300)
emit("gsl_bzero", "gsl", list(cases))
