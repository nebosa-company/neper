# gsl: lnpoch, lnpoch_sgn, poch and pochrel with error estimates.
#   "p" (code, part, a, x): part 0 value, 1 error, 2 sign (lnpoch_sgn); code 0 lnpoch, 1 poch, 2 pochrel, 3 lnpoch_sgn
suppressMessages(library(gsl))
cases <- list()
set.seed(20262954)
add <- function(code, a, x, r, vrel = 1e-10, erel = 1e-8) {
  if (is.null(r) || r$status != 0 || !is.finite(r$val)) return()
  cases[[length(cases) + 1]] <<- case("p", c(code, 0, a, x), r$val, rel = vrel, abs = 1e-12)
  cases[[length(cases) + 1]] <<- case("p", c(code, 1, a, x), r$err, rel = erel, abs = 1e-300)
  if (!is.null(r$sgn)) cases[[length(cases) + 1]] <<- case("p", c(code, 2, a, x), r$sgn, rel = 0, abs = 0.5)
}
g <- function(f, ...) tryCatch(f(..., give = TRUE, strict = FALSE), error = function(e) NULL)
for (i in 1:120) {
  a <- c(runif(1, 0.01, 2), runif(1, 2, 15), runif(1, 15, 300), runif(1, 300, 5000))[sample(1:4, 1)]
  x <- c(runif(1, -0.9, 0.9) * min(a, 1) * 0.5, runif(1, -1, 1) * 1e-3, runif(1, 0, 12), runif(1, 0, 0.05 * a))[sample(1:4, 1)]
  if (a + x > 0 && x != 0) { add(0, a, x, g(lnpoch, a, x)); add(1, a, x, g(poch, a, x), vrel = 1e-9); add(2, a, x, g(pochrel, a, x), vrel = 1e-9) }
  an <- -runif(1, 0.05, 12); xn <- c(runif(1, -3, 3), runif(1, -1e-3, 1e-3))[sample(1:2, 1)]
  if (abs(an - round(an)) > 0.02 && abs(an + xn - round(an + xn)) > 0.02 && xn != 0) {
    add(2, an, xn, g(pochrel, an, xn), vrel = 1e-8); add(1, an, xn, g(poch, an, xn), vrel = 1e-9)
    add(3, an, xn, g(lnpoch_sgn, an, xn), vrel = 1e-9)
  }
  if (a + x > 0 && x != 0) add(3, a, x, g(lnpoch_sgn, a, x))
}
for (v in list(c(-3, 2), c(-3, -1), c(-4, 4), c(-2, 1), c(5, 0), c(-5, -2))) add(1, v[1], v[2], g(poch, v[1], v[2]))
emit("gslpoch", "gsl", list(cases))
