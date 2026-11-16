# locfit local polynomial regression, tricube kernel, evaluated at the data points (ev = dat()).
#   args: (n, nn, h, deg, x[n] sorted, y[n]); h > 0 selects a fixed bandwidth, otherwise nn
#   fn "fit" (fitted values weighted by position), "rss" (residual sum of squares)
suppressMessages(library(locfit))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-6, abs = 1e-8)
set.seed(20261228)
for (rep in 1:24) {
  n <- sample(30:120, 1); x <- sort(round(runif(n), 5)); y <- sin(4 * x) + rnorm(n, 0, 0.3); deg <- sample(0:3, 1)
  fixed <- rep %% 3 == 0; nn <- runif(1, 0.3, 0.9); h <- if (fixed) runif(1, 0.12, 0.4) else 0
  f <- if (fixed) locfit(y ~ lp(x, h = h, deg = deg), ev = dat(), kern = "tricube") else locfit(y ~ lp(x, nn = nn, deg = deg), ev = dat(), kern = "tricube")
  p <- as.numeric(fitted(f)); a <- c(n, nn, h, deg, x, y)
  add("fit", a, sum(p * seq_along(p))); add("rss", a, sum((y - p)^2))
}
emit("locfit", "locfit", list(cases))
