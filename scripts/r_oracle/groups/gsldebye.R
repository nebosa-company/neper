# gsl: Debye functions 1 to 4 with error estimates.
#   "y" (n, part, x): part 0 value, 1 error
suppressMessages(library(gsl))
cases <- list()
set.seed(20262926)
fl <- list(debye_1, debye_2, debye_3, debye_4)
for (i in 1:80) {
  x <- c(10^runif(1, -9, -6), runif(1, 0, 4), runif(1, 4, 30), runif(1, 30, 200), runif(1, 200, 800))[sample(1:5, 1)]
  for (n in 1:4) {
    r <- fl[[n]](x, give = TRUE, strict = FALSE)
    if (r$status != 0 || r$val == 0) next
    cases[[length(cases) + 1]] <- case("y", c(n, 0, x), r$val, rel = 1e-11, abs = 1e-300)
    cases[[length(cases) + 1]] <- case("y", c(n, 1, x), r$err, rel = 1e-8, abs = 1e-300)
  }
}
emit("gsldebye", "gsl", list(cases))
