# gsl: the Airy functions and their derivatives, plain and scaled, with error estimates in the three precision modes.
#   "a" (code, part, mode, x): part 0 value, 1 error; code 0 Ai, 1 Ai_scaled, 2 Bi, 3 Bi_scaled, 4 Ai_deriv, 5 Ai_deriv_scaled, 6 Bi_deriv, 7 Bi_deriv_scaled
suppressMessages(library(gsl))
cases <- list()
set.seed(20262918)
fl <- list(airy_Ai, airy_Ai_scaled, airy_Bi, airy_Bi_scaled, airy_Ai_deriv, airy_Ai_deriv_scaled, airy_Bi_deriv, airy_Bi_deriv_scaled)
for (i in 1:70) {
  x <- c(runif(1, -40, -4), runif(1, -4, -1), runif(1, -1, 1), runif(1, 1, 2), runif(1, 2, 4), runif(1, 4, 40))[sample(1:6, 1)]
  for (mode in 0:2) for (code in 0:7) {
    r <- tryCatch(fl[[code + 1]](x, mode = mode, give = TRUE, strict = FALSE), error = function(e) NULL)
    if (is.null(r) || r$status != 0 || !is.finite(r$val)) next
    cases[[length(cases) + 1]] <- case("a", c(code, 0, mode, x), r$val, rel = 1e-10, abs = 1e-300)
    cases[[length(cases) + 1]] <- case("a", c(code, 1, mode, x), r$err, rel = 1e-8, abs = 1e-300)
  }
}
emit("gslairy", "gsl", list(cases))
