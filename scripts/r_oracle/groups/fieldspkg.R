# fieldspkg: fields' Matern covariance and Exp.cov.
#   "matern" (d, range, smoothness, phi); "expcov" (d, range, p, 0)
suppressMessages(library(fields))
cases <- list()
add <- function(fn, args, want, rel = 1e-9) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = rel, abs = 1e-12)
set.seed(20262009)
for (rep in 1:30) {
  rg <- runif(1, 0.3, 3); nu <- sample(c(0.5, 1.5, 2.5, runif(2, 0.2, 4)), 1); phi <- runif(1, 0.5, 3)
  for (d in c(0, runif(4, 0.01, 6))) add("matern", c(d, rg, nu, phi), Matern(d, range = rg, smoothness = nu, phi = phi), if (d == 0 && !(nu %in% c(0.5, 1.5, 2.5))) 1e-8 else 1e-9)
  p <- runif(1, 0.5, 2)
  for (d in runif(3, 0, 5)) add("expcov", c(d, rg, p, 0), Exp.cov(matrix(0, 1, 1), matrix(d, 1, 1), aRange = rg, p = p)[1, 1])
}
emit("fieldspkg", "fields", list(cases))
