# performancepkg: performance indices of an lm. The mae is mean(abs(resid)), which performance_mae returns when run on its own but which came back NaN inside generate.R.
#   args: (which 0 r2, 1 r2_adjusted, 2 rmse, 3 mae, 4 mse, 5 sigma, 6 loglik, 7 aic, 8 aicc, 9 bic; n; p; y (n); x row-major n by p with the intercept column)
suppressMessages(library(performance))
cases <- list()
add <- function(fn, args, want) cases[[length(cases) + 1]] <<- case(fn, args, want, rel = 1e-9, abs = 1e-11)
set.seed(20262012)
for (rep in 1:25) {
  n <- sample(20:120, 1); p <- sample(2:5, 1); X <- cbind(1, matrix(round(rnorm(n * (p - 1)), 4), n, p - 1)); y <- round(as.vector(X %*% runif(p, -1, 1)) + rnorm(n), 4)
  m <- lm(y ~ X[, -1, drop = FALSE])
  v <- c(r2(m)$R2, r2(m)$R2_adjusted, performance_rmse(m), mean(abs(resid(m))), performance_mse(m), sigma(m), as.numeric(logLik(m)), performance_aic(m), performance_aicc(m), BIC(m))
  for (w in 0:9) add("lm", c(w, n, p, y, as.vector(t(X))), as.numeric(v[w + 1]))
}
# check_heteroscedasticity ("het": n, p, y, x row-major with the intercept) and check_collinearity ("vif": n, q, j, x row-major without it)
for (rep in 1:25) {
  n <- sample(30:120, 1); p <- sample(3:5, 1); X <- cbind(1, matrix(round(rnorm(n * (p - 1)), 4), n, p - 1))
  X[, 3] <- round(X[, 2] * runif(1, 0.3, 1.2) + rnorm(n, 0, 0.6), 4)
  y <- round(as.vector(X %*% runif(p, -1, 1)) + rnorm(n) * (1 + 0.5 * abs(X[, 2])), 4)
  m <- lm(y ~ X[, -1, drop = FALSE])
  cases[[length(cases) + 1]] <- case("het", c(n, p, y, as.vector(t(X))), as.numeric(check_heteroscedasticity(m)), rel = 1e-8, abs = 1e-12)
  q <- p - 1; xx <- X[, -1, drop = FALSE]; dfm <- as.data.frame(xx); names(dfm) <- paste0("v", 1:q)
  yy <- y; mm <- lm(as.formula(paste("yy ~", paste(names(dfm), collapse = " + "))), data = cbind(dfm, yy = yy))
  cc <- suppressMessages(check_collinearity(mm))
  for (j in 1:q) cases[[length(cases) + 1]] <- case("vif", c(n, q, j - 1, as.vector(t(xx))), as.numeric(cc$VIF[j]), rel = 1e-8, abs = 1e-12)
}
# pseudo R2 of a logistic regression ("lr2": which 0 Tjur 1 Cox-Snell 2 Nagelkerke 3 McFadden 4 McFadden adjusted, n, p, y, x row-major with the intercept)
for (rep in 1:25) {
  n <- sample(40:150, 1); p <- sample(2:4, 1); X <- cbind(1, matrix(round(rnorm(n * (p - 1)), 4), n, p - 1))
  y <- rbinom(n, 1, plogis(as.vector(X %*% runif(p, -1, 1)))); if (length(unique(y)) < 2) next
  dfx <- as.data.frame(X[, -1, drop = FALSE]); names(dfx) <- paste0("v", seq_len(p - 1)); dfx$y <- y
  m <- glm(as.formula(paste("y ~", paste(names(dfx)[-p], collapse = " + "))), data = dfx, family = binomial)
  v <- c(r2_tjur(m)[[1]], r2_coxsnell(m)[[1]], r2_nagelkerke(m)[[1]], r2_mcfadden(m)$R2[[1]], r2_mcfadden(m)$R2_adjusted[[1]])
  for (w in 0:4) cases[[length(cases) + 1]] <- case("lr2", c(w, n, p, y, as.vector(t(X))), as.numeric(v[w + 1]), rel = 1e-8, abs = 1e-12)
}
# check_normality of an lm ("norm": n, p, y, x row-major with the intercept): the Shapiro-Wilk p value of rstandard
for (rep in 1:25) {
  n <- sample(20:200, 1); p <- sample(2:4, 1); X <- cbind(1, matrix(round(rnorm(n * (p - 1)), 4), n, p - 1))
  e <- if (rep %% 2 == 0) rnorm(n) else rexp(n) - 1
  y <- round(as.vector(X %*% runif(p, -1, 1)) + e, 4)
  dfx <- as.data.frame(X[, -1, drop = FALSE]); names(dfx) <- paste0("v", seq_len(p - 1)); dfx$y <- y
  m <- lm(as.formula(paste("y ~", paste(names(dfx)[-p], collapse = " + "))), data = dfx)
  cases[[length(cases) + 1]] <- case("norm", c(n, p, y, as.vector(t(X))), as.numeric(suppressMessages(check_normality(m))), rel = 1e-8, abs = 1e-12)
}
emit("performancepkg", "performance", list(cases))
