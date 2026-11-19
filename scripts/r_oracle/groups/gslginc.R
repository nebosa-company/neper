# gsl: gamma_inc, gamma_inc_P, gamma_inc_Q (every branch) and beta_inc (a, b > 0) with error estimates.
#   "g" (code, part, a, b, x): part 0 value, 1 error; code 0 gamma_inc(a, x), 1 gamma_inc_P, 2 gamma_inc_Q, 3 beta_inc(a, b, x)
suppressMessages(library(gsl))
cases <- list()
set.seed(20262955)
add <- function(code, a, b, x, r, vrel = 1e-10, erel = 1e-8) {
  if (is.null(r) || r$status != 0 || !is.finite(r$val) || r$val == 0) return()
  cases[[length(cases) + 1]] <<- case("g", c(code, 0, a, b, x), r$val, rel = vrel, abs = 1e-300)
  cases[[length(cases) + 1]] <<- case("g", c(code, 1, a, b, x), r$err, rel = erel, abs = 1e-300)
}
g <- function(f, ...) tryCatch(f(..., give = TRUE, strict = FALSE), error = function(e) NULL)
for (i in 1:200) {
  a <- c(runif(1, 0.01, 0.2), runif(1, 0.2, 3), runif(1, 3, 30), runif(1, 30, 1000), 10^runif(1, 3, 5.5), 10^runif(1, 6, 7))[sample(1:6, 1)]
  x <- c(a * runif(1, 0, 0.5), a * runif(1, 0.5, 1), a * runif(1, 1, 1.5), runif(1, 0, 6), runif(1, 20, 60), a + sqrt(a) * runif(1, -3, 3))[sample(1:6, 1)]
  if (x <= 0) x <- 0.5
  add(1, a, 0, x, g(gamma_inc_P, a, x)); add(2, a, 0, x, g(gamma_inc_Q, a, x))
  if (a < 200) add(0, a, 0, x, g(gamma_inc, a, x), vrel = 1e-9)
  an <- -runif(1, 0.01, 6); xn <- c(runif(1, 0.01, 0.25), runif(1, 0.25, 8))[sample(1:2, 1)]
  if (abs(an - round(an)) > 0.01) add(0, an, 0, xn, g(gamma_inc, an, xn), vrel = 1e-9)
  b <- runif(1, 0.1, 40); xb <- runif(1, 0.001, 0.999)
  ab <- runif(1, 0.1, 40)
  add(3, ab, b, xb, g(beta_inc, ab, b, xb))
}
add(0, 0, 0, 1.5, g(gamma_inc, 0, 1.5)); add(0, 2, 0, 0, g(gamma_inc, 2, 0))
emit("gslginc", "gsl", list(cases))
