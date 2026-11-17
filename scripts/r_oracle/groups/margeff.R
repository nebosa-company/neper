# marginaleffects for glms: avg_slopes, avg_predictions and avg_comparisons (a 0 / 1 variable) with delta-method standard errors, from the fitted coefficients.
#   args: (n, p, j (0-based slope column, or p for the average prediction), which 0 estimate 1 se, link 0 identity 1 logit 2 log, kind 0 slope or prediction 1 comparison, beta[p], vcov[p p], X[n p] with the intercept column)
suppressMessages(library(marginaleffects))
cases <- list()
set.seed(20261204)
add <- function(a, est, tol = 1e-5) cases[[length(cases) + 1]] <<- case("ame", a, est, rel = tol, abs = 1e-8)
for (rep in 1:18) {
  link <- rep %% 3; n <- sample(80:200, 1); k <- sample(2:3, 1); X <- matrix(round(rnorm(n * k), 3), n, k); X[, 1] <- rbinom(n, 1, 0.5)
  eta <- 0.3 + X %*% c(0.6, -0.4, 0.3)[1:k] * 0.8
  y <- if (link == 0) as.vector(eta) + rnorm(n) else if (link == 1) rbinom(n, 1, plogis(eta)) else rpois(n, exp(eta * 0.6))
  d <- data.frame(y = y, X); names(d) <- c("y", paste0("v", 1:k)); fam <- list(gaussian, binomial, poisson)[[link + 1]]
  m <- glm(as.formula(paste("y ~", paste0("v", 1:k, collapse = " + "))), fam, d)
  Xm <- cbind(1, X); b <- coef(m); V <- vcov(m); p <- length(b)
  sl <- as.data.frame(avg_slopes(m, variables = paste0("v", 1:k))); ap <- as.data.frame(avg_predictions(m))
  for (j in 2:k) for (w in 0:1) add(c(n, p, j, w, link, 0, b, V, Xm), if (w == 0) sl$estimate[j] else sl$std.error[j])
  for (w in 0:1) add(c(n, p, p, w, link, 0, b, V, Xm), if (w == 0) ap$estimate[1] else ap$std.error[1])
  cmp <- as.data.frame(avg_comparisons(m, variables = list(v1 = 0:1)))
  for (w in 0:1) add(c(n, p, 1, w, link, 1, b, V, Xm), if (w == 0) cmp$estimate[1] else cmp$std.error[1])
}
emit("margeff", "marginaleffects", list(cases))
