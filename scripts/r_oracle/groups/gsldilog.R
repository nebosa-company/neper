# gsl: the real dilogarithm with its error estimate.
#   "d" (part, x): part 0 value, 1 error
suppressMessages(library(gsl))
cases <- list()
set.seed(20262920)
for (i in 1:120) {
  x <- c(runif(1, -50, -2), runif(1, -2, -0.5), runif(1, -0.5, 0), runif(1, 0, 0.25), runif(1, 0.25, 0.5), runif(1, 0.5, 1), 1 + 10^runif(1, -8, -2), runif(1, 1.01, 2), runif(1, 2, 500))[sample(1:9, 1)]
  r <- dilog(x, give = TRUE, strict = FALSE)
  cases[[length(cases) + 1]] <- case("d", c(0, x), r$val, rel = 1e-11, abs = 1e-300)
  cases[[length(cases) + 1]] <- case("d", c(1, x), r$err, rel = 1e-9, abs = 1e-300)
}
for (x in c(0, 1, -1, 0.5, 0.25, 2, 1.01)) { r <- dilog(x, give = TRUE, strict = FALSE); cases[[length(cases) + 1]] <- case("d", c(0, x), r$val, rel = 1e-11, abs = 1e-300); cases[[length(cases) + 1]] <- case("d", c(1, x), r$err, rel = 1e-9, abs = 1e-300) }
emit("gsldilog", "gsl", list(cases))
