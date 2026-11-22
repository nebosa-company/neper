# R's nmath special functions against this runtime, bit for bit. These are R's portable C code (not the
# platform libm), so unlike exp/log/pow they CAN match exactly on every host.
#   fn: "lgamma", "gamma", "erf", "erfc", "pnorm", "qnorm"
#   want: R's value, compared bit for bit
suppressMessages(library(Rmpfr))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 0, abs = 0)
set.seed(20270202)
n <- 400
for (x in c(runif(n, 1e-3, 20), runif(n / 2, 0.5, 3), 10^runif(n / 4, -2, 4))) {
  add("lgamma", x, lgamma(x))
  add("gamma", x, gamma(x))
}
for (x in c(runif(n, -6, 6), rnorm(n / 2), seq(-4, 4, by = 0.1))) {
  add("erf", x, erf(x))
  add("erfc", x, erfc(x))
  add("pnorm", x, pnorm(x))
}
for (p in c(runif(n, 1e-12, 1 - 1e-12), 10^runif(n / 4, -12, -1))) add("qnorm", p, qnorm(p))
emit("math_nmath", c("Rmpfr", "gmp"), list(cases))
