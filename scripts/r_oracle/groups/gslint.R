# gsl: Si, Ci, Shi, Chi, atanint and expint_3 with error estimates.
#   "i" (code, part, x): part 0 value, 1 error; code 0 Si, 1 Ci, 2 Shi, 3 Chi, 4 atanint, 5 expint_3
suppressMessages(library(gsl))
cases <- list()
set.seed(20262925)
fl <- list(Si, Ci, Shi, Chi, atanint, expint_3)
for (i in 1:100) {
  x <- c(runif(1, 0, 0.4), runif(1, 0.4, 4), runif(1, 4, 7.1), runif(1, 7.1, 100), 10^runif(1, 3, 9), 10^runif(1, -9, -3))[sample(1:6, 1)]
  for (code in 0:5) {
    xx <- if (code %in% c(0, 2, 4) && sample(c(TRUE, FALSE), 1)) -x else x
    if (code == 5 && x > 6) xx <- x
    r <- tryCatch(fl[[code + 1]](xx, give = TRUE, strict = FALSE), error = function(e) NULL)
    if (is.null(r) || r$status != 0 || !is.finite(r$val)) next
    cases[[length(cases) + 1]] <- case("i", c(code, 0, xx), r$val, rel = 1e-10, abs = 1e-14)
    cases[[length(cases) + 1]] <- case("i", c(code, 1, xx), r$err, rel = 1e-8, abs = 1e-300)
  }
}
emit("gslint", "gsl", list(cases))
