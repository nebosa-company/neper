# VGAM vglm(y ~ x1 + ... + xp, multinomial): "mn" args (n, p, J, y[n] 0-based, x[n*p] row-major, k) k the coefficients class by class (intercept then slopes, last level the reference), then the log-likelihood, then the standard errors in the coefficient order
suppressMessages(library(VGAM))
cases <- list()
set.seed(20271211)
for (rep in 1:20) {
  n <- sample(150:400, 1); p <- sample(1:3, 1); J <- sample(3:5, 1); X <- matrix(round(rnorm(n * p), 3), n, p)
  B <- matrix(rnorm((p + 1) * J, 0, 0.7), p + 1, J); B[, J] <- 0
  eta <- cbind(1, X) %*% B; pr <- exp(eta) / rowSums(exp(eta)); y <- apply(pr, 1, function(r) sample(0:(J - 1), 1, prob = r))
  if (length(unique(y)) < J) next
  d <- as.data.frame(X); names(d) <- paste0("x", 1:p); d$y <- factor(y, levels = 0:(J - 1))
  f <- tryCatch(vglm(as.formula(paste("y ~", paste0("x", 1:p, collapse = " + "))), multinomial(refLevel = J), data = d), error = function(e) NULL)
  if (is.null(f)) next
  cf <- as.vector(t(matrix(coef(f), nrow = J - 1))); V <- vcov(f); se <- as.vector(t(matrix(sqrt(diag(V)), nrow = J - 1)))
  v <- c(cf, as.numeric(logLik(f)), se)
  for (k in seq_along(v)) cases[[length(cases) + 1]] <- case("mn", c(n, p, J, y, as.vector(t(X)), k - 1), v[k], rel = 5e-4, abs = 1e-5)
}
emit("vgam_multinom", "VGAM", list(cases))
