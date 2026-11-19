# gsl: erf, erfc, log_erfc, erf_Q and hazard with error estimates.
#   "f" (code, part, x): part 0 value, 1 error; code 0 erf, 1 erfc, 2 log_erfc, 3 erf_Q, 4 hazard
suppressMessages(library(gsl))
cases <- list()
set.seed(20262923)
fl <- list(erf, erfc, log_erfc, erf_Q, hazard)
for (i in 1:100) {
  x <- c(runif(1, -1, 1), runif(1, -5, 5), runif(1, 5, 10), runif(1, 10, 26), runif(1, -10, -5), runif(1, -0.1, 0.1))[sample(1:6, 1)]
  for (code in 0:4) {
    r <- tryCatch(fl[[code + 1]](x, give = TRUE, strict = FALSE), error = function(e) NULL)
    if (is.null(r) || r$status != 0 || !is.finite(r$val) || r$val == 0) next
    cases[[length(cases) + 1]] <- case("f", c(code, 0, x), r$val, rel = 1e-11, abs = 1e-300)
    cases[[length(cases) + 1]] <- case("f", c(code, 1, x), r$err, rel = 1e-8, abs = 1e-300)
  }
}
emit("gslerf", "gsl", list(cases))
