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
# check_outliers distances: "zs" (robust 0/1, n, q, X row-major, row), "mah" (0, n, q, X, row), "cook" (n, p, y, X with intercept, row)
for (rep in 1:20) {
  n <- sample(15:80, 1); q <- sample(2:4, 1); Xm <- matrix(round(rnorm(n * q), 4), n, q); Xm[sample(n, 2), 1] <- Xm[sample(n, 2), 1] + 6
  df <- as.data.frame(Xm)
  zr <- performance:::.check_outliers_zscore(df, robust = TRUE)$data_zscore_robust$Distance_Zscore_robust
  zc <- performance:::.check_outliers_zscore(df, robust = FALSE)$data_zscore$Distance_Zscore
  md <- mahalanobis(Xm, colMeans(Xm), cov(Xm))
  for (i in sample(n, 4)) {
    cases[[length(cases) + 1]] <- case("zs", c(1, n, q, as.vector(t(Xm)), i - 1), zr[i], rel = 1e-9, abs = 1e-12)
    cases[[length(cases) + 1]] <- case("zs", c(0, n, q, as.vector(t(Xm)), i - 1), zc[i], rel = 1e-9, abs = 1e-12)
    cases[[length(cases) + 1]] <- case("mah", c(0, n, q, as.vector(t(Xm)), i - 1), md[i], rel = 1e-8, abs = 1e-12)
  }
  p <- q; X <- cbind(1, Xm[, -1, drop = FALSE]); y <- round(as.vector(X %*% runif(p, -1, 1)) + rnorm(n), 4)
  cd <- cooks.distance(lm(y ~ X - 1))
  for (i in sample(n, 4)) cases[[length(cases) + 1]] <- case("cook", c(n, p, y, as.vector(t(X)), i - 1), cd[i], rel = 1e-8, abs = 1e-12)
}
# logistic fit measures ("hl": bins, n, p, y, x row-major; index 0 chi-square, 1 p value after x. "lm2": which 0 Efron 1 log loss)
for (rep in 1:25) {
  n <- sample(60:200, 1); p <- sample(2:4, 1); X <- cbind(1, matrix(round(rnorm(n * (p - 1)), 4), n, p - 1))
  y <- rbinom(n, 1, plogis(as.vector(X %*% runif(p, -1, 1)))); if (length(unique(y)) < 2) next
  dfx <- as.data.frame(X[, -1, drop = FALSE]); names(dfx) <- paste0("v", seq_len(p - 1)); dfx$y <- y
  m <- glm(as.formula(paste("y ~", paste(names(dfx)[-p], collapse = " + "))), data = dfx, family = binomial)
  bins <- sample(c(5, 8, 10), 1); hl <- performance_hosmer(m, n_bins = bins)
  cases[[length(cases) + 1]] <- case("hl", c(bins, n, p, y, as.vector(t(X)), 0), hl$chisq, rel = 1e-8, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("hl", c(bins, n, p, y, as.vector(t(X)), 1), hl$p.value, rel = 1e-8, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("lm2", c(0, n, p, y, as.vector(t(X))), as.numeric(r2_efron(m)), rel = 1e-8, abs = 1e-12)
  cases[[length(cases) + 1]] <- case("lm2", c(1, n, p, y, as.vector(t(X))), as.numeric(performance_logloss(m)), rel = 1e-8, abs = 1e-12)
}
# Poisson checks ("pchk": which 0 dispersion ratio, 1 chi-square, 2 p, 3 observed zeros, 4 predicted zeros, 5 ratio; n, p, y, X row-major with the intercept)
for (rep in 1:25) {
  n <- sample(40:120, 1); p <- sample(2:3, 1); Xm <- matrix(round(rnorm(n * (p - 1)), 3), n, p - 1); X <- cbind(1, Xm)
  y <- rnbinom(n, mu = exp(0.5 + 0.3 * Xm[, 1]), size = 2)
  dfx <- as.data.frame(Xm); names(dfx) <- paste0("v", seq_len(p - 1)); dfx$y <- y
  m <- glm(as.formula(paste("y ~", paste(names(dfx)[-p], collapse = " + "))), data = dfx, family = poisson)
  od <- suppressMessages(check_overdispersion(m)); zi <- suppressMessages(check_zeroinflation(m))
  v <- c(od$dispersion_ratio, od$chisq_statistic, od$p_value, zi$observed.zeros, zi$predicted.zeros, zi$ratio)
  for (w in 0:5) cases[[length(cases) + 1]] <- case("pchk", c(w, n, p, y, as.vector(t(X))), as.numeric(v[w + 1]), rel = 1e-7, abs = 1e-10)
}
# standardize_parameters of an lm (numeric predictors): "stdp" (n, p, level, j, which 0 slope 1 lower 2 upper, y[n], x row-major n by p)
suppressMessages(library(parameters)); suppressMessages(library(effectsize))
for (rep in 1:15) {
  n <- sample(25:100, 1); p <- sample(1:4, 1); X <- matrix(round(rnorm(n * p), 3), n, p); colnames(X) <- paste0("x", 1:p)
  y <- round(as.vector(X %*% runif(p, -1, 1)) + rnorm(n), 3); d <- data.frame(y = y, X); lev <- sample(c(0.9, 0.95, 0.99), 1)
  r <- as.data.frame(suppressMessages(standardize_parameters(lm(y ~ ., d), method = "refit", ci = lev)))
  for (j in 1:p) for (w in 0:2) cases[[length(cases) + 1]] <- case("stdp", c(n, p, lev, j - 1, w, y, as.vector(t(X))), r[j + 1, c("Std_Coefficient", "CI_low", "CI_high")[w + 1]], rel = 1e-8, abs = 1e-10)
}
# performance_pcp and r2_mckelvey of a logistic regression: "pcp" (which 0..8 as logit_pcp, n, p, y, x row-major with the intercept)
for (rep in 1:20) {
  n <- sample(60:200, 1); p <- sample(2:4, 1); X <- cbind(1, matrix(round(rnorm(n * (p - 1)), 3), n, p - 1)); y <- rbinom(n, 1, plogis(as.vector(X %*% c(0, runif(p - 1, -1, 1)))))
  if (sum(y) < 10 || sum(y) > n - 10) next
  dd <- data.frame(y = y, X[, -1, drop = FALSE]); names(dd) <- c("y", paste0("x", seq_len(p - 1))); m <- glm(y ~ ., data = dd, family = binomial); pc <- as.data.frame(performance_pcp(m))
  v <- c(pc$Estimate[1], pc$Estimate[2], pc$CI_low[1], pc$CI_high[1], pc$CI_low[2], pc$CI_high[2], pc$Chisq[2], pc$p[2], as.numeric(r2_mckelvey(m)), as.numeric(r2_kullback(m)), as.numeric(r2_kullback(m, adjust = FALSE)))
  for (w in 0:10) cases[[length(cases) + 1]] <- case("pcp", c(w, n, p, y, as.vector(t(X))), as.numeric(v[w + 1]), rel = 1e-6, abs = 1e-10)
}
emit("performancepkg", "performance", list(cases))
