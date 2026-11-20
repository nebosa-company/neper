# gsl: conicalP_0, conicalP_1, conicalP_sph_reg, conicalP_cyl_reg, conicalP_half and conicalP_mhalf with gsl's error estimates (strict = FALSE, give = TRUE).
#   "con" (code, part, n, lambda, x): code 0 conicalP_0, 1 conicalP_1, 2 sph_reg(l = n), 3 cyl_reg(m = n) (the CRAN wrapper reaches gsl_sf_conicalP_sph_reg_e, so these equal code 2), 4 half, 5 mhalf; part 0 value, 1 error
suppressMessages(library(gsl))
cases <- list()
set.seed(20263001)
g <- function(code, n, lam, x) tryCatch(switch(code + 1,
  conicalP_0(lam, x, give = TRUE, strict = FALSE), conicalP_1(lam, x, give = TRUE, strict = FALSE),
  conicalP_sph_reg(n, lam, x, give = TRUE, strict = FALSE), conicalP_cyl_reg(n, lam, x, give = TRUE, strict = FALSE),
  conicalP_half(lam, x, give = TRUE, strict = FALSE), conicalP_mhalf(lam, x, give = TRUE, strict = FALSE)), error = function(e) NULL)
add <- function(code, n, lam, x, vrel = 1e-10, erel = 1e-8) {
  r <- g(code, n, lam, x)
  if (is.null(r) || r$status != 0 || !is.finite(r$val) || !is.finite(r$err)) return()
  cases[[length(cases) + 1]] <<- case("con", c(code, 0, n, lam, x), r$val, rel = vrel, abs = 1e-300)
  cases[[length(cases) + 1]] <<- case("con", c(code, 1, n, lam, x), r$err, rel = erel, abs = 1e-300)
}
pick <- function() {
  lam <- c(0, runif(1, 0.01, 5), runif(1, 5, 17), runif(1, 17, 25), runif(1, 25, 60), runif(1, 60, 150))[sample(1:6, 1, prob = c(1, 3, 3, 3, 3, 2))]
  x <- c(runif(1, -0.95, 0), runif(1, 0, 0.2), runif(1, 0.2, 1), runif(1, 1, 1.5), runif(1, 1.5, 6), runif(1, 6, 50), 1 - 10^runif(1, -9, -3), 1 + 10^runif(1, -9, -3))[sample(1:8, 1, prob = c(2, 1, 3, 2, 3, 1, 1, 1))]
  if (abs(x - 1) < 1e-3 && lam >= 17) lam <- runif(1, 0.01, 10)   # the Kolbig expansion cancels catastrophically there, so gsl answers libm noise
  c(lam, x)
}
for (i in 1:220) { p <- pick(); add(0, 0, p[1], p[2]); p <- pick(); add(1, 0, p[1], p[2]) }
for (i in 1:60) { p <- pick(); add(2, sample(1:30, 1), p[1], p[2]); p <- pick(); add(3, sample(1:30, 1), p[1], p[2]) }
for (i in 1:25) { p <- pick(); add(2, sample(c(-1, 0), 1), p[1], p[2]); p <- pick(); add(3, sample(c(-1, 0), 1), p[1], p[2]) }
for (i in 1:40) { p <- pick(); add(4, 0, p[1], p[2]); p <- pick(); add(5, 0, p[1], p[2]) }
add(0, 0, 3, 1); add(1, 0, 0, 1); add(0, 0, 0, 1); add(0, 0, 2, 1)
emit("gslcon", "gsl", list(cases))
