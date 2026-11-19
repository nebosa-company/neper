# gsl: synchrotron_1, synchrotron_2 and transport_2 to transport_5 with error estimates.
#   "s" (code, part, x): part 0 value, 1 error; code 0 synchrotron_1, 1 synchrotron_2, 2 to 5 transport_n
suppressMessages(library(gsl))
cases <- list()
set.seed(20262953)
fl <- list(synchrotron_1, synchrotron_2, transport_2, transport_3, transport_4, transport_5)
for (i in 1:100) {
  x <- c(10^runif(1, -12, -6), runif(1, 1e-6, 1), runif(1, 1, 4), runif(1, 4, 36), runif(1, 36, 300), 10^runif(1, 2.5, 18))[sample(1:6, 1)]
  for (code in 0:5) {
    if (code <= 1 && x > 300) next
    r <- tryCatch(fl[[code + 1]](x, give = TRUE, strict = FALSE), error = function(e) NULL)
    if (is.null(r) || r$status != 0 || !is.finite(r$val) || r$val == 0) next
    cases[[length(cases) + 1]] <- case("s", c(code, 0, x), r$val, rel = 1e-11, abs = 1e-300)
    cases[[length(cases) + 1]] <- case("s", c(code, 1, x), r$err, rel = 1e-9, abs = 1e-300)
  }
}
emit("gslsync", "gsl", list(cases))
