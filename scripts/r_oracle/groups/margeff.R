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
# further links: 3 binomial probit, 4 binomial cloglog, 5 Gamma inverse, 6 poisson sqrt
set.seed(20262493)
for (rep in 1:20) {
  link <- 3 + rep %% 4; n <- sample(120:250, 1); k <- sample(2:3, 1); X <- matrix(round(rnorm(n * k), 3), n, k); X[, 1] <- rbinom(n, 1, 0.5)
  eta <- 0.3 + X %*% c(0.6, -0.4, 0.3)[1:k] * 0.8
  y <- if (link == 3) rbinom(n, 1, pnorm(eta)) else if (link == 4) rbinom(n, 1, 1 - exp(-exp(eta))) else if (link == 5) rgamma(n, 4, 4 * (0.9 + 0.15 * X[, 2])) else rpois(n, (0.8 + 0.15 * X[, 2])^2 * 3)
  d <- data.frame(y = y, X); names(d) <- c("y", paste0("v", 1:k))
  fam <- list(binomial(link = "probit"), binomial(link = "cloglog"), Gamma(link = "inverse"), poisson(link = "sqrt"))[[link - 2]]
  m <- tryCatch(suppressWarnings(glm(as.formula(paste("y ~", paste0("v", 1:k, collapse = " + "))), fam, d)), error = function(e) NULL)
  if (is.null(m) || !m$converged) next
  Xm <- cbind(1, X); b <- coef(m); V <- vcov(m); p <- length(b)
  if (link == 5 && any(Xm %*% b <= 0.05)) next
  sl <- as.data.frame(avg_slopes(m, variables = paste0("v", 1:k))); ap <- as.data.frame(avg_predictions(m))
  for (j in 2:k) for (w in 0:1) add(c(n, p, j, w, link, 0, b, V, Xm), if (w == 0) sl$estimate[j] else sl$std.error[j])
  for (w in 0:1) add(c(n, p, p, w, link, 0, b, V, Xm), if (w == 0) ap$estimate[1] else ap$std.error[1])
  cmp <- as.data.frame(avg_comparisons(m, variables = list(v1 = 0:1)))
  for (w in 0:1) add(c(n, p, 1, w, link, 1, b, V, Xm), if (w == 0) cmp$estimate[1] else cmp$std.error[1])
}
# predictions at new rows: "mpred" args (p, link, beta[p], vcov[p p], x row[p], which 0 estimate 1 se)
set.seed(20262494)
for (rep in 1:30) {
  link <- rep %% 7; n <- sample(100:200, 1); k <- sample(2:3, 1); X <- matrix(round(rnorm(n * k), 3), n, k); X[, 1] <- rbinom(n, 1, 0.5)
  eta <- 0.3 + X %*% c(0.6, -0.4, 0.3)[1:k] * 0.8
  y <- switch(link + 1, as.vector(eta) + rnorm(n), rbinom(n, 1, plogis(eta)), rpois(n, exp(eta * 0.6)), rbinom(n, 1, pnorm(eta)), rbinom(n, 1, 1 - exp(-exp(eta))), rgamma(n, 4, 4 * (0.9 + 0.15 * X[, 2])), rpois(n, (0.8 + 0.15 * X[, 2])^2 * 3))
  d <- data.frame(y = y, X); names(d) <- c("y", paste0("v", 1:k))
  fam <- list(gaussian(), binomial(), poisson(), binomial(link = "probit"), binomial(link = "cloglog"), Gamma(link = "inverse"), poisson(link = "sqrt"))[[link + 1]]
  m <- tryCatch(suppressWarnings(glm(as.formula(paste("y ~", paste0("v", 1:k, collapse = " + "))), fam, d)), error = function(e) NULL)
  if (is.null(m) || !m$converged) next
  b <- coef(m); V <- vcov(m); p <- length(b)
  nd <- data.frame(matrix(round(rnorm(4 * k), 2), 4, k)); names(nd) <- paste0("v", 1:k)
  pr <- tryCatch(as.data.frame(predictions(m, newdata = nd)), error = function(e) NULL)
  if (is.null(pr)) next
  for (r in 1:4) { xr <- c(1, as.numeric(nd[r, ])); for (w in 0:1) { v <- if (w == 0) pr$estimate[r] else if ("std.error" %in% names(pr)) pr$std.error[r] else NA_real_; if (length(v) == 1 && is.finite(v)) cases[[length(cases) + 1]] <- case("mpred", c(p, link, b, V, xr, w), v, rel = 1e-5, abs = 1e-8) } }
}
# hypotheses with equality constraints: "mhyp" args (p, q, beta[p], vcov[p p], r[p], which 0 estimate 1 se 2 z 3 p)
options(marginaleffects_safe = FALSE)
set.seed(20262495)
for (rep in 1:30) {
  n <- sample(60:150, 1); k <- sample(2:4, 1); X <- matrix(round(rnorm(n * k), 3), n, k); d <- data.frame(y = X %*% c(0.5, -0.3, 0.2, 0.1)[1:k] + rnorm(n), X); names(d) <- c("y", paste0("v", 1:k))
  m <- glm(as.formula(paste("y ~", paste0("v", 1:k, collapse = " + "))), gaussian, d); b <- coef(m); V <- vcov(m); p <- length(b)
  rv <- sample(c(-2, -1, 0, 1, 2), p, TRUE); if (all(rv == 0)) rv[1] <- 1; qv <- sample(c(0, 0.5, -1), 1)
  hyp <- paste0(paste0(ifelse(rv < 0, "-", "+"), abs(rv), "*b", seq_len(p), collapse = ""), "=", qv)
  h <- tryCatch(as.data.frame(hypotheses(m, hypothesis = hyp)), error = function(e) NULL)
  if (is.null(h)) next
  vals <- c(h$estimate[1], h$std.error[1], h$statistic[1], h$p.value[1])
  for (w in 0:3) if (is.finite(vals[w + 1])) cases[[length(cases) + 1]] <- case("mhyp", c(p, qv, b, V, rv, w), vals[w + 1], rel = 1e-6, abs = 1e-9)
}
# unit-change comparisons of a continuous variable: the "ame" layout with kind 2
options(marginaleffects_safe = FALSE)
set.seed(20262496)
for (rep in 1:21) {
  link <- rep %% 7; n <- sample(100:220, 1); k <- sample(2:3, 1); X <- matrix(round(rnorm(n * k), 3), n, k); X[, 1] <- rbinom(n, 1, 0.5)
  eta <- 0.3 + X %*% c(0.6, -0.4, 0.3)[1:k] * 0.8
  y <- switch(link + 1, as.vector(eta) + rnorm(n), rbinom(n, 1, plogis(eta)), rpois(n, exp(eta * 0.6)), rbinom(n, 1, pnorm(eta)), rbinom(n, 1, 1 - exp(-exp(eta))), rgamma(n, 4, 4 * (0.9 + 0.15 * X[, 2])), rpois(n, (0.8 + 0.15 * X[, 2])^2 * 3))
  d <- data.frame(y = y, X); names(d) <- c("y", paste0("v", 1:k))
  fam <- list(gaussian(), binomial(), poisson(), binomial(link = "probit"), binomial(link = "cloglog"), Gamma(link = "inverse"), poisson(link = "sqrt"))[[link + 1]]
  m <- tryCatch(suppressWarnings(glm(as.formula(paste("y ~", paste0("v", 1:k, collapse = " + "))), fam, d)), error = function(e) NULL)
  if (is.null(m) || !m$converged) next
  Xm <- cbind(1, X); b <- coef(m); V <- vcov(m); p <- length(b)
  if (link == 5 && any(Xm %*% b <= 0.05)) next
  cmp <- tryCatch(as.data.frame(avg_comparisons(m, variables = list(v2 = 1))), error = function(e) NULL)
  if (is.null(cmp)) next
  for (w in 0:1) { v <- if (w == 0) cmp$estimate[1] else cmp$std.error[1]; if (is.finite(v)) add(c(n, p, 2, w, link, 2, b, V, Xm), v) }
}
emit("margeff", "marginaleffects", list(cases))
