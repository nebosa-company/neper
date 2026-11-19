# gsl: legendre_H3d_0, legendre_H3d_1, legendre_H3d and legendre_H3d_array with error estimates (the branches that use the conical-function asymptotics are skipped).
#   "h" (code, part, l, lambda, eta, lmax): part 0 value, 1 error; code 0 H3d_0, 1 H3d_1, 2 H3d(l), 3 H3d_array element l of lmax (value only)
suppressMessages(library(gsl))
cases <- list()
set.seed(20262959)
g <- function(f, ...) tryCatch(f(..., give = TRUE, strict = FALSE), error = function(e) NULL)
add <- function(code, l, lam, eta, lmax, r, vrel = 1e-10, erel = 1e-8) {
  if (is.null(r) || r$status != 0 || !is.finite(r$val)) return()
  cases[[length(cases) + 1]] <<- case("h", c(code, 0, l, lam, eta, lmax), r$val, rel = vrel, abs = 1e-300)
  if (!is.null(r$err)) cases[[length(cases) + 1]] <<- case("h", c(code, 1, l, lam, eta, lmax), r$err, rel = erel, abs = 1e-300)
}
asym <- function(l, lam, eta) { lsq <- lam^2; (l * l + lsq) / sqrt(1 + lsq) / cosh(eta)^2 < 5 * 6.0554544523933429e-06 || abs(lam) > 1000 * l * l }
for (i in 1:200) {
  lam <- c(runif(1, 0.01, 1), runif(1, 1, 8), runif(1, 8, 60), 10^runif(1, -6, -3))[sample(1:4, 1)]
  eta <- c(runif(1, 1e-6, 1e-3), runif(1, 1e-3, 0.4), runif(1, 0.4, 4), runif(1, 4, 40))[sample(1:4, 1)]
  add(0, 0, lam, eta, 0, g(legendre_H3d_0, lam, eta)); add(1, 0, lam, eta, 0, g(legendre_H3d_1, lam, eta), vrel = min(1e-6, max(1e-10, 50 * 2.2e-16 / eta^2)))  # H3d_1 subtracts two terms equal to O(eta^2): gsl itself carries 2e-16/eta^2 of noise, which a different libm moves
  l <- sample(2:40, 1)
  if (!asym(l, lam, eta)) add(2, l, lam, eta, 0, g(legendre_H3d, l, lam, eta), vrel = 1e-9)
}
for (i in 1:30) {
  lam <- runif(1, 0.2, 6); eta <- runif(1, 0.3, 3); lmax <- sample(2:12, 1)
  if (asym(lmax, lam, eta)) next
  arr <- tryCatch(as.vector(legendre_H3d_array(lmax, lam, eta)), error = function(e) NULL)
  if (is.null(arr)) next
  for (l in 0:lmax) cases[[length(cases) + 1]] <- case("h", c(3, 0, l, lam, eta, lmax), arr[l + 1], rel = 1e-8, abs = 1e-300)
}
emit("gslh3d", "gsl", list(cases))
