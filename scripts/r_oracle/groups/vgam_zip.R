# VGAM vglm(y ~ x1 + ... + xp, zipoissonff(zero = -2)): "zip" args (n, p, y[n], x[n*p] row-major without the intercept, k) k 0..p the intercept and slopes of the log mean, p + 1 the logit of the structural zero probability (VGAM models the logit of its complement, so its sign is flipped here), p + 2 the log-likelihood
suppressMessages(library(VGAM))
cases <- list()
set.seed(20271214)
for (rep in 1:10) {
  n <- sample(150:300, 1); p <- sample(1:2, 1); X <- matrix(round(rnorm(n * p), 3), n, p)
  lam <- exp(0.5 + as.vector(X %*% runif(p, -0.5, 0.5))); phi <- runif(1, 0.1, 0.5); y <- ifelse(runif(n) < phi, 0, rpois(n, lam))
  d <- as.data.frame(X); names(d) <- paste0("x", 1:p); d$y <- y
  f <- tryCatch(vglm(as.formula(paste("y ~", paste0("x", 1:p, collapse = " + "))), zipoissonff(zero = -2), data = d, control = vglm.control(epsilon = 1e-12, maxit = 200)), error = function(e) NULL)
  if (is.null(f)) next
  cf <- coef(f); v <- c(cf[1], cf[3:(p + 2)], -cf[2], as.numeric(logLik(f)))
  for (k in seq_along(v)) cases[[length(cases) + 1]] <- case("zip", c(n, p, y, as.vector(t(X)), k - 1), as.numeric(v[k]), rel = 1e-4, abs = 1e-5)
}
emit("vgam_zip", "VGAM", list(cases))
