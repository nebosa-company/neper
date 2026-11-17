# marginaleffects for a logistic regression: avg_slopes and avg_predictions with delta-method standard errors, from the fitted coefficients.
#   args: (n, p, j (0-based slope column, or p for the average prediction), which 0 estimate 1 se, beta[p], vcov[p p], X[n p] with the intercept column)
suppressMessages(library(marginaleffects))
cases <- list()
set.seed(20261204)
for (rep in 1:12) {
  n <- sample(60:200, 1); k <- sample(2:3, 1); X <- matrix(round(rnorm(n * k), 3), n, k); eta <- 0.3 + X %*% c(0.6, -0.4, 0.3)[1:k]; y <- rbinom(n, 1, plogis(eta))
  d <- data.frame(y = y, X); names(d) <- c("y", paste0("v", 1:k)); m <- glm(as.formula(paste("y ~", paste0("v", 1:k, collapse = " + "))), binomial, d)
  Xm <- cbind(1, X); b <- coef(m); V <- vcov(m); p <- length(b)
  sl <- as.data.frame(avg_slopes(m)); ap <- as.data.frame(avg_predictions(m))
  for (j in 1:k) for (w in 0:1) cases[[length(cases) + 1]] <- case("ame", c(n, p, j, w, b, V, Xm), if (w == 0) sl$estimate[j] else sl$std.error[j], rel = 1e-5, abs = 1e-8)
  for (w in 0:1) cases[[length(cases) + 1]] <- case("ame", c(n, p, p, w, b, V, Xm), if (w == 0) ap$estimate[1] else ap$std.error[1], rel = 1e-5, abs = 1e-8)
}
emit("margeff", "marginaleffects", list(cases))
