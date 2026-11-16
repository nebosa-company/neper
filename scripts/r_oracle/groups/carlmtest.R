# car, lmtest, sandwich: vcovHC (HC0 to HC4), dwtest, studentized bptest and vif of a linear model.
#   args: (n, p, y[n]..., X row-major n by p with the intercept column...)   fn "hc0" .. "hc4" (sum of diag(vcovHC) * position), "dw", "bp", "vif" (sum of vif * position)
suppressMessages({library(car); library(lmtest); library(sandwich)})
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-8, abs = 1e-12)
set.seed(20261228)
for (rep in 1:12) {
  n <- sample(20:70, 1); k <- sample(2:4, 1)
  X <- matrix(rnorm(n * k), n, k); for (j in 2:k) X[, j] <- X[, j] + 0.6 * X[, j - 1]
  y <- 1 + X %*% (1:k / 2) + rnorm(n) * (1 + abs(X[, 1])); colnames(X) <- paste0("v", 1:k)
  d <- data.frame(y = as.vector(y), X); m <- lm(y ~ ., d)
  des <- cbind(1, X); a <- c(n, k + 1, as.vector(y), as.vector(t(des)))
  for (t in 0:4) { dv <- diag(vcovHC(m, paste0("HC", t))); add(paste0("hc", t), a, sum(dv * seq_along(dv))) }
  add("dw", a, as.numeric(dwtest(m)$statistic)); add("bp", a, as.numeric(bptest(m)$statistic))
  if (k >= 2) { v <- vif(m); add("vif", a, sum(v * seq_along(v))) }
}
emit("carlmtest", "car", list(cases))
