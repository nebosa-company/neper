# forecast: BoxCox, InvBoxCox, BoxCox.lambda(method = "loglik") on a plain numeric series.
#   "bc" (x, lambda) ; "ibc" (x, lambda) ; "lam" (n, x[n], lower, upper)
suppressMessages(library(forecast))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-10, abs = 1e-12)
for (lam in c(-1, -0.5, -0.1, 0, 0.3, 0.5, 1, 2)) for (x in c(0.01, 0.5, 1, 2.5, 10, 100)) {
  add("bc", c(x, lam), as.numeric(BoxCox(x, lam)))
  add("ibc", c(x, lam), as.numeric(suppressWarnings(InvBoxCox(BoxCox(x, lam), lam))))
}
for (x in c(-2, -0.5, 0, 0.5, 2)) for (lam in c(0.5, 1, 2)) add("bc", c(x, lam), as.numeric(BoxCox(x, lam)))
set.seed(20261116)
for (rep in 1:30) {
  n <- sample(8:60, 1); x <- round(exp(rnorm(n, 2, runif(1, 0.1, 1.2))) + runif(1, 0, 5), 3)
  add("lam", c(n, x, -1, 2), BoxCox.lambda(x, method = "loglik", lower = -1, upper = 2))
  add("lam", c(n, x, -0.5, 1), BoxCox.lambda(x, method = "loglik", lower = -0.5, upper = 1))
}
emit("fcast", "forecast", list(cases))
