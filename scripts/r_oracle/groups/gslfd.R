# gsl: the Fermi-Dirac integrals with error estimates.
#   "f" (code, part, a, b): part 0 value, 1 error; code 0 m1(a), 1 0, 2 1, 3 2, 4 mhalf, 5 half, 6 3half, 7 int(j = a, x = b), 8 inc_0(x = a, b = b)
suppressMessages(library(gsl))
cases <- list()
set.seed(20262952)
fl <- list(fermi_dirac_m1, fermi_dirac_0, fermi_dirac_1, fermi_dirac_2, fermi_dirac_mhalf, fermi_dirac_half, fermi_dirac_3half)
add <- function(code, a, b, r, vrel = 1e-10, erel = 1e-8) {
  if (is.null(r) || r$status != 0 || !is.finite(r$val) || r$val == 0) return()
  cases[[length(cases) + 1]] <<- case("f", c(code, 0, a, b), r$val, rel = vrel, abs = 1e-300)
  cases[[length(cases) + 1]] <<- case("f", c(code, 1, a, b), r$err, rel = erel, abs = 1e-300)
}
g <- function(f, ...) tryCatch(f(..., give = TRUE, strict = FALSE), error = function(e) NULL)
for (i in 1:60) {
  x <- c(runif(1, -40, -1), runif(1, -1, 1), runif(1, 1, 4), runif(1, 4, 10), runif(1, 10, 30), runif(1, 30, 200), runif(1, 200, 1e5))[sample(1:7, 1)]
  for (code in 0:6) add(code, x, 0, g(fl[[code + 1]], x))
  j <- sample(c(-6:-2, 3:14), 1); xj <- c(runif(1, -30, 0), runif(1, 0, 1.5), runif(1, 1.5, 50), runif(1, 50, 300))[sample(1:4, 1)]
  add(7, j, xj, g(fermi_dirac_int, j, xj), vrel = 1e-9, erel = 1e-6)
  b <- runif(1, 0, 20); add(8, x, b, g(fermi_dirac_inc_0, x, b))
}
add(7, 5, 0, g(fermi_dirac_int, 5, 0))
# integer order err: for x < 0 and the asymptotic series err is |f - f_previous| of the Levin-u iteration, a rounding-level difference, so it is compared at 1e-6. Recorded failing case at erel = 1e-8: fermi_dirac_int(8, 6.020023795310408) err, got 1.466894614229207e-11, R 1.4668945708611146e-11 (3e-8 relative)
emit("gslfd", "gsl", list(cases))
