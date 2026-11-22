# R's exp, log and pow on sampled doubles: the reference for the shared runtime's special functions.
#   args: for exp/log one argument, for pow two
#   want: R's value, compared bit for bit (rel 0, abs 0) so any last-bit disagreement shows up
suppressMessages(library(Rmpfr))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 0, abs = 0)
set.seed(20270201)
n <- 500
# exp: the whole double range, plus negatives and fractions
xe <- c(runif(n, -700, 700), runif(n / 10, -1, 1), -runif(n / 10, 0, 700), seq(-20, 20, by = 0.25))
for (x in xe) add("exp", x, exp(x))
# log: positives over many decades, and values near one
xl <- c(exp(runif(n, -700, 700)), runif(n / 5, 0.5, 2), 10^runif(n / 5, -300, 300), 0.012788335265094734)
for (x in xl) add("log", x, log(x))
# pow: positive bases with fractional exponents, where R uses the platform's pow
xp <- exp(runif(n / 2, -50, 50)); yp <- runif(n / 2, -30, 30)
# pow from MPFR: R's own pow is not always correctly rounded, so the reference is the exact value
for (i in seq_along(xp)) add("pow", c(xp[i], yp[i]), as.numeric(exp(mpfr(yp[i], 400) * log(mpfr(xp[i], 400)))))
emit("math_libm", c("Rmpfr", "gmp"), list(cases))
