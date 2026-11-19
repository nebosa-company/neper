# gsl: bessel_zero_Jnu(nu, s) and the integer-order bessel_zero_J0 / J1. Args: (nu, s)
suppressMessages(library(gsl))
cases <- list()
set.seed(20262430)
for (rep in 1:60) {
  nu <- c(0, 1, runif(1, 0, 4), runif(1, 0, 8))[rep %% 4 + 1]; s <- sample(1:20, 1); if (nu != floor(nu)) s <- sample(1:2, 1)
  r <- tryCatch(bessel_zero_Jnu(nu, s), error = function(e) NA)
  if (is.finite(r)) cases[[length(cases) + 1]] <- case("zj", c(nu, s), r, rel = 1e-10, abs = 1e-10)
}
emit("gsl_bzero", "gsl", list(cases))
