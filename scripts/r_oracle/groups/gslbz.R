# gsl: bessel_zero_J0, J1, Jnu (outside the Olver branch) and the four airy_zero_* with error estimates.
#   "z" (code, part, nu, s): part 0 value, 1 error; code 0 J0, 1 J1, 2 Jnu, 3 Ai, 4 Bi, 5 Ai', 6 Bi'
suppressMessages(library(gsl))
cases <- list()
set.seed(20263101)
add <- function(code, nu, s, r) {
  if (is.null(r) || r$status != 0 || !is.finite(r$val)) return()
  cases[[length(cases) + 1]] <<- case("z", c(code, 0, nu, s), r$val, rel = 1e-12, abs = 1e-300)
  cases[[length(cases) + 1]] <<- case("z", c(code, 1, nu, s), r$err, rel = 1e-9, abs = 1e-300)
}
g <- function(f, ...) tryCatch(f(..., give = TRUE, strict = FALSE), error = function(e) NULL)
for (s in c(1:30, 50, 100, 1000, 100000)) {
  add(0, 0, s, g(bessel_zero_J0, s))
  add(1, 0, s, g(bessel_zero_J1, s))
}
for (s in c(1:70, 200, 5000)) {
  add(3, 0, s, g(airy_zero_Ai, s)); add(4, 0, s, g(airy_zero_Bi, s))
  add(5, 0, s, g(airy_zero_Ai_deriv, s)); add(6, 0, s, g(airy_zero_Bi_deriv, s))
}
n <- 0
while (n < 400) {
  nu <- c(0, 1, runif(1, 0, 3), runif(1, 0, 12), runif(1, 0, 40), runif(1, 0, 2))[sample(1:6, 1)]
  s <- sample(c(1:25, 30, 60, 200), 1)
  if (s > 10 && !(s > 0.5 * nu && s <= 20) && !(s > 2 * nu)) next
  r <- g(bessel_zero_Jnu, nu, s)
  if (!is.null(r)) { add(2, nu, s, r); n <- n + 1 }
}
emit("gslbz", "gsl", list(cases))
