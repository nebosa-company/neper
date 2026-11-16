# drc: drm(y ~ dose, fct = LL.4()) estimates and residual sum of squares.
#   args: (n, dose[n]..., resp[n]...)   fn "b" "c" "d" "e" "rss"; agreement is to the optimiser tolerance (drm stops at its own criteria)
suppressMessages(library(drc))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = if (fn == "rss") 1e-5 else 3e-3, abs = 1e-6)
set.seed(20261229)
for (rep in 1:20) {
  dose <- rep(c(0.1, 0.3, 1, 3, 10, 30, 100), each = sample(2:4, 1)); n <- length(dose)
  b <- runif(1, 0.8, 3) * sample(c(1, -1), 1, prob = c(0.8, 0.2)); cc <- runif(1, 0, 3); d <- cc + runif(1, 4, 12); e <- exp(runif(1, log(0.8), log(30)))
  y <- round(cc + (d - cc) / (1 + exp(b * (log(dose) - log(e)))) + rnorm(n, 0, 0.25), 4)
  m <- try(suppressWarnings(drm(y ~ dose, fct = LL.4())), silent = TRUE)
  if (inherits(m, "try-error")) next
  cf <- as.numeric(coef(m)); a <- c(n, dose, y)
  add("b", a, cf[1]); add("c", a, cf[2]); add("d", a, cf[3]); add("e", a, cf[4]); add("rss", a, sum(residuals(m)^2))
}
emit("drc", "drc", list(cases))
