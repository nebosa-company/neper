# rpart (anova, xval = 0): number of leaves and fitted values of a regression tree on numeric predictors.
#   args: (n, p, minsplit, minbucket, cp, y[n]..., x row-major n by p...)   fn "nleaf" "fit" (the fitted values weighted by position)
suppressMessages(library(rpart))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-10)
set.seed(20261233 %% 100000)
for (rep in 1:30) {
  n <- sample(40:150, 1); p <- sample(1:4, 1); X <- matrix(round(runif(n * p), 4), n, p)
  y <- round(3 * (X[, 1] > 0.5) + (if (p > 1) 2 * (X[, 2] > 0.3) else 0) + (if (p > 2) X[, 3] else 0) + rnorm(n) * c(0.3, 0.8)[rep %% 2 + 1], 4)
  ms <- sample(c(10, 20, 30), 1); mb <- sample(c(3, 5, 7), 1); cp <- sample(c(0.01, 0.02, 0.05), 1)
  d <- data.frame(y = y, X); fit <- rpart(y ~ ., d, method = "anova", control = rpart.control(minsplit = ms, minbucket = mb, cp = cp, xval = 0))
  a <- c(n, p, ms, mb, cp, y, as.vector(t(X)))
  add("nleaf", a, sum(fit$frame$var == "<leaf>")); pr <- predict(fit, d); add("fit", a, sum(pr * seq_along(pr)))
}
emit("cart", "rpart", list(cases))
