# xgboost reg:squarederror, exact tree method, one thread, no sampling.
#   args: (n, p, nrounds, eta, depth, lambda, gamma, min_child_weight, y[n], x[n*p] row-major)
#   fn "pred" (training predictions weighted by position), "rmse" (training RMSE)
suppressMessages(library(xgboost))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-4, abs = 1e-5)
set.seed(20261225)
for (rep in 1:20) {
  n <- sample(40:150, 1); p <- sample(2:5, 1); nr <- sample(1:12, 1); eta <- sample(c(0.1, 0.3, 0.5, 1), 1); dep <- sample(1:5, 1)
  lam <- sample(c(0, 0.5, 1, 3), 1); gam <- sample(c(0, 0, 0.5, 2), 1); mcw <- sample(c(0.5, 1, 3), 1)
  x <- matrix(round(rnorm(n * p), 4), n); y <- round(x[, 1] + x[, 2]^2 - x[, p] * 0.5 + rnorm(n, 0, 0.3), 4)
  dm <- xgb.DMatrix(x, label = y)
  m <- xgb.train(params = list(objective = "reg:squarederror", eta = eta, max_depth = dep, lambda = lam, gamma = gam, min_child_weight = mcw, tree_method = "exact", nthread = 1, base_score = mean(y)), data = dm, nrounds = nr, verbose = 0)
  pr <- predict(m, dm)
  a <- c(n, p, nr, eta, dep, lam, gam, mcw, y, as.vector(t(x)))
  add("pred", a, sum(pr * seq_along(pr))); add("rmse", a, sqrt(mean((pr - y)^2)))
}
emit("xgboost", "xgboost", list(cases))
