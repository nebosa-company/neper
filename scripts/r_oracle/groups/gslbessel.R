# gsl: the modified Bessel functions of order 0 and 1 with error estimates.
#   "b" (code, part, x): part 0 value, 1 error; code 0 I0, 1 I0_scaled, 2 I1, 3 I1_scaled, 4 K0, 5 K0_scaled, 6 K1, 7 K1_scaled
suppressMessages(library(gsl))
cases <- list()
set.seed(20262919)
fl <- list(bessel_I0, bessel_I0_scaled, bessel_I1, bessel_I1_scaled, bessel_K0, bessel_K0_scaled, bessel_K1, bessel_K1_scaled)
for (i in 1:80) {
  x <- c(runif(1, 0, 1), runif(1, 1, 3), runif(1, 3, 8), runif(1, 8, 100), runif(1, 100, 700), 10^runif(1, -9, -3))[sample(1:6, 1)]
  for (code in 0:7) {
    xx <- if (code < 4 && sample(c(TRUE, FALSE), 1)) -x else x
    r <- tryCatch(fl[[code + 1]](xx, give = TRUE, strict = FALSE), error = function(e) NULL)
    if (is.null(r) || r$status != 0 || !is.finite(r$val)) next
    cases[[length(cases) + 1]] <- case("b", c(code, 0, xx), r$val, rel = 1e-11, abs = 1e-300)
    cases[[length(cases) + 1]] <- case("b", c(code, 1, xx), r$err, rel = 1e-8, abs = 1e-300)
  }
}
emit("gslbessel", "gsl", list(cases))
