# gsl: Lambert W and Hurwitz zeta with error estimates.
#   "w" (code, part, a, b): part 0 value, 1 error; code 0 lambert_W0(a), 1 lambert_Wm1(a), 2 hzeta(s = a, q = b)
suppressMessages(library(gsl))
cases <- list()
set.seed(20262916)
add2 <- function(code, args, r) {
  cases[[length(cases) + 1]] <<- case("w", c(code, 0, args), r$val, rel = 1e-11, abs = 1e-300)
  cases[[length(cases) + 1]] <<- case("w", c(code, 1, args), r$err, rel = 1e-9, abs = 1e-300)
}
g <- function(f, ...) f(..., give = TRUE, strict = FALSE)
for (i in 1:60) {
  x <- c(runif(1, -0.3678, 1), runif(1, 1, 60), 10^runif(1, 2, 10), -0.36787944 + 10^runif(1, -9, -3.1), 10^runif(1, -12, -2))[sample(1:5, 1)]
  add2(0, c(x, 0), g(lambert_W0, x))
  xm <- c(-runif(1, 0.0001, 0.3678), -10^runif(1, -12, -4), -0.36787944 + 10^runif(1, -9, -3.1))[sample(1:3, 1)]
  add2(1, c(xm, 0), g(lambert_Wm1, xm))
  s <- c(runif(1, 1.01, 10), runif(1, 10, 40), runif(1, 28, 120))[sample(1:3, 1)]; q <- c(runif(1, 0.01, 0.3), runif(1, 0.3, 1), runif(1, 1, 12))[sample(1:3, 1)]
  r <- tryCatch(g(hzeta, s, q), error = function(e) NULL); if (!is.null(r) && r$status == 0) add2(2, c(s, q), r)
}
emit("gslw", "gsl", list(cases))
